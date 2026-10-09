#!/usr/bin/env node
/**
 * A rough SVG approximation of what VeraPreview.ets would draw.
 *
 * This is NOT VeraPreview.ets running headless -- that file is @Component/
 * ArkUI and cannot execute outside ArkUI. This is a small, honest
 * approximation: boxes sized from estimated text width (not real ArkUI text
 * metrics), real colors pulled from VeraTheme's resolved theme, and
 * left-to-right wrapping at an assumed viewport width for the handful of
 * node kinds that wrap in the real renderer. No animation, no exact
 * padding/radius pixel values, no device color profile.
 *
 * It exists so a layout change -- does this row wrap or run off the edge? --
 * can be judged by eye in a few seconds, instead of waiting on a signed,
 * installed build. For anything the approximation can't speak to (exact
 * ArkUI measurement, real device color, animation), CLAUDE.md's on-device
 * path is still the one to use.
 *
 * Usage:
 *   node run.js some.vera | node proof-sheet.js > out.svg
 *   node proof-sheet.js --select-wrap=false < tree.json > before.svg
 */
'use strict'

const { resolveTheme } = require('./out/VeraTheme')

const VIEWPORT_WIDTH = 360
const PADDING = 12

// Kinds the real renderer wraps onto new lines rather than overflowing.
// 'select' is listed here because this is what it SHOULD do (Flex wrap) --
// see the --select-wrap flag below for reproducing the pre-fix behaviour.
const WRAP_KINDS = new Set(['row', 'actionbar', 'grid', 'metricgroup', 'kvgroup', 'select'])

function readStdin() {
  const chunks = []
  process.stdin.on('data', (c) => chunks.push(c))
  return new Promise((resolve) => {
    process.stdin.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')))
  })
}

function estimateTextWidth(text, fontSize) {
  return Math.max(1, text.length) * fontSize * 0.56
}

function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

/**
 * Lay out one node's children left-to-right, wrapping at `maxWidth`, and
 * return { svg, width, height } for the whole row of lines.
 */
function layoutWrappingRow(children, maxWidth, gap, selectWrap) {
  const lineHeight = 28
  let x = 0, y = 0, lineH = 0
  const placed = []
  for (const child of children) {
    const box = layoutNode(child, maxWidth, selectWrap)
    const wraps = selectWrap !== false
    if (wraps && x > 0 && x + box.width > maxWidth) {
      x = 0
      y += lineH + gap
      lineH = 0
    }
    placed.push({ box, x, y })
    x += box.width + gap
    lineH = Math.max(lineH, box.height)
  }
  const totalHeight = y + lineH
  const totalWidth = selectWrap === false
    ? placed.reduce((w, p) => Math.max(w, p.x + p.box.width), 0)
    : maxWidth
  let svg = ''
  for (const p of placed) {
    svg += `<g transform="translate(${p.x},${p.y})">${p.box.svg}</g>`
  }
  return { svg, width: totalWidth, height: Math.max(totalHeight, lineHeight) }
}

function layoutColumn(children, maxWidth, selectWrap) {
  let y = 0
  let svg = ''
  for (const child of children) {
    const box = layoutNode(child, maxWidth, selectWrap)
    svg += `<g transform="translate(0,${y})">${box.svg}</g>`
    y += box.height + 6
  }
  return { svg, width: maxWidth, height: y }
}

function colorFor(theme, tone, fallback) {
  const map = {
    success: theme.success, warning: theme.warning, danger: theme.danger,
    accent: theme.primary, muted: theme.inkMuted
  }
  return map[tone] || fallback
}

function layoutNode(node, maxWidth, selectWrap) {
  const theme = global.__theme
  if (!node) return { svg: '', width: 0, height: 0 }

  if (node.kind === 'apptheme' || node.kind === 'column' || node.kind === 'card' ||
      node.kind === 'section' || node.kind === 'listgroup' || node.kind === 'scroll' ||
      node.kind === 'header' || node.kind === 'timeline') {
    const inner = layoutColumn(node.children, maxWidth - 2 * PADDING, selectWrap)
    const fill = node.kind === 'card' || node.kind === 'listgroup' ? theme.surface : 'none'
    const label = node.text ? `<text x="4" y="14" font-size="13" fill="${theme.ink}">${esc(node.text)}</text>` : ''
    const label2 = node.label ? `<text x="4" y="${node.text ? 30 : 14}" font-size="11" fill="${theme.inkMuted}">${esc(node.label)}</text>` : ''
    const yOff = (node.text ? 18 : 0) + (node.label ? 16 : 0)
    const h = inner.height + yOff + 2 * PADDING
    const rect = fill !== 'none' ? `<rect width="${maxWidth}" height="${h}" fill="${fill}" rx="8"/>` : ''
    return {
      svg: `${rect}${label}${label2}<g transform="translate(${PADDING},${PADDING + yOff})">${inner.svg}</g>`,
      width: maxWidth, height: h
    }
  }

  if (WRAP_KINDS.has(node.kind)) {
    const wrap = node.kind === 'select' ? selectWrap : true
    const items = node.kind === 'select'
      ? node.options.map((opt, i) => ({ kind: 'button', style: i === node.eventValue ? 'primary' : 'secondary', text: opt, children: [] }))
      : node.children
    const inner = layoutWrappingRow(items, maxWidth, 8, wrap)
    const labelH = node.label ? 16 : 0
    const label = node.label ? `<text x="0" y="12" font-size="11" fill="${theme.inkMuted}">${esc(node.label)}</text>` : ''
    return {
      svg: `${label}<g transform="translate(0,${labelH})">${inner.svg}</g>`,
      width: inner.width, height: inner.height + labelH
    }
  }

  if (node.kind === 'button' || node.kind === 'iconbutton') {
    const fill = node.style === 'primary' ? theme.primary
      : node.style === 'danger' ? theme.danger
      : node.style === 'success' ? theme.success
      : theme.secondaryFill
    const ink = node.style === 'primary' || node.style === 'danger' || node.style === 'success'
      ? theme.onPrimary : theme.secondaryInk
    const w = estimateTextWidth(node.text || ' ', 14) + 24
    return {
      svg: `<rect width="${w}" height="36" rx="18" fill="${fill}"/>` +
        `<text x="${w / 2}" y="23" font-size="14" text-anchor="middle" fill="${ink}">${esc(node.text)}</text>`,
      width: w, height: 36
    }
  }

  if (node.kind === 'text' || node.kind === 'inttext' || node.kind === 'clocktext') {
    const size = { display: 30, title: 24, heading: 18, metric: 32, caption: 12 }[node.style] || 15
    const ink = colorFor(theme, node.style, theme.ink)
    const w = estimateTextWidth(node.text || '0', size)
    return {
      svg: `<text x="0" y="${size}" font-size="${size}" fill="${ink}">${esc(node.text || node.intValue)}</text>`,
      width: Math.min(w, maxWidth), height: size + 8
    }
  }

  if (node.kind === 'spacer') {
    const h = { small: 8, large: 32 }[node.style] || 18
    return { svg: '', width: 1, height: node.style === 'none' ? 0 : h }
  }

  if (node.kind === 'divider') {
    return { svg: `<line x1="0" y1="0" x2="${maxWidth}" y2="0" stroke="${theme.line}"/>`, width: maxWidth, height: 1 }
  }

  if (node.kind === 'sparkline') {
    const w = maxWidth, h = 72
    const max = Math.max(node.maximum || 100, ...(node.series || [0]))
    const series = node.series || []
    const n = series.length
    const color = colorFor(theme, node.style, theme.primary)
    if (node.bars) {
      const spacing = n > 1 ? w / (n - 1) : w
      const barWidth = Math.min(spacing * 0.6, w * 0.2)
      const rects = series.map((v, i) => {
        const cx = n > 1 ? (i / (n - 1)) * w : w / 2
        const py = h - (Math.min(v, max) / max) * h
        return `<rect x="${(cx - barWidth / 2).toFixed(1)}" y="${py.toFixed(1)}" ` +
          `width="${barWidth.toFixed(1)}" height="${(h - py).toFixed(1)}" fill="${color}"/>`
      }).join('')
      return { svg: rects, width: w, height: h }
    }
    const pts = series.map((v, i) => {
      const px = n > 1 ? (i / (n - 1)) * w : w / 2
      const py = h - (Math.min(v, max) / max) * h
      return `${px.toFixed(1)},${py.toFixed(1)}`
    }).join(' ')
    return {
      svg: `<polyline points="${pts}" fill="none" stroke="${color}" stroke-width="2"/>`,
      width: w, height: h
    }
  }

  if (node.kind === 'slider') {
    const w = maxWidth, h = 20, trackY = 9, trackH = 4
    const frac = Math.max(0, Math.min(1, ((node.eventValue - node.minimum) /
      Math.max(1, (node.maximum - node.minimum)))))
    const color = colorFor(theme, node.style, theme.primary)
    const labelH = node.label ? 16 : 0
    const label = node.label
      ? `<text x="0" y="12" font-size="11" fill="${theme.inkMuted}">${esc(node.label)}</text>` : ''
    return {
      svg: `${label}<g transform="translate(0,${labelH})">` +
        `<rect y="${trackY}" width="${w}" height="${trackH}" rx="2" fill="${theme.secondaryFill}"/>` +
        `<rect y="${trackY}" width="${(w * frac).toFixed(1)}" height="${trackH}" rx="2" fill="${color}"/>` +
        `<circle cx="${(w * frac).toFixed(1)}" cy="${trackY + trackH / 2}" r="7" fill="${color}"/>` +
        `</g>`,
      width: w, height: h + labelH
    }
  }

  if (node.kind === 'table') {
    const headers = node.options || []
    const cols = Math.max(1, node.columns || headers.length || 1)
    const colW = maxWidth / cols
    let y = 0
    let svg = ''
    let bgs = ''
    let text = ''
    if (headers.length > 0) {
      text += headers.map((hText, i) =>
        `<text x="${(i * colW + 4).toFixed(1)}" y="12" font-size="11" font-weight="bold" ` +
        `fill="${theme.inkMuted}">${esc(hText)}</text>`).join('')
      y += 22
    }
    for (const row of node.children || []) {
      const cells = row.options || []
      const rowFill = colorFor(theme, row.style, null)
      if (rowFill) {
        bgs += `<rect y="${y}" width="${maxWidth}" height="22" fill="${rowFill}" opacity="0.25"/>`
      }
      text += cells.map((c, i) =>
        `<text x="${(i * colW + 4).toFixed(1)}" y="${y + 14}" font-size="13" ` +
        `fill="${theme.ink}">${esc(c)}</text>`).join('')
      y += 22
    }
    return {
      // Paint order: outer frame, then row tints, then text on top.
      svg: `<rect width="${maxWidth}" height="${y}" fill="none" stroke="${theme.line}" rx="6"/>${bgs}${text}`,
      width: maxWidth, height: y
    }
  }

  // Fallback: everything else as a labeled box, so a kind this script hasn't
  // learned yet is still visible rather than silently dropped.
  const text = node.text || node.label || node.kind
  const w = Math.min(estimateTextWidth(text, 14) + 16, maxWidth)
  return {
    svg: `<rect width="${w}" height="24" fill="${theme.surface}" stroke="${theme.line}"/>` +
      `<text x="4" y="16" font-size="12" fill="${theme.inkMuted}">${esc(node.kind)}: ${esc(text)}</text>`,
    width: w, height: 28
  }
}

async function main() {
  const args = process.argv.slice(2)
  const selectWrapArg = args.find((a) => a.startsWith('--select-wrap='))
  const selectWrap = selectWrapArg ? selectWrapArg.split('=')[1] !== 'false' : true
  const presetArg = args.find((a) => a.startsWith('--preset='))
  const preset = presetArg ? presetArg.split('=')[1] : 'clean'

  const input = await readStdin()
  const tree = JSON.parse(input)
  const theme = resolveTheme(preset, '', false)
  global.__theme = theme

  const box = layoutNode(tree, VIEWPORT_WIDTH, selectWrap)
  const width = VIEWPORT_WIDTH
  const height = box.height + 2 * PADDING
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">` +
    `<rect width="${width}" height="${height}" fill="${theme.background}"/>` +
    `<g transform="translate(0,${PADDING})">${box.svg}</g>` +
    `</svg>`
  process.stdout.write(svg + '\n')
}

main()
