/**
 * The renderer's own copy of the UI tree, and the reconciler that keeps it in
 * step with what the program produced.
 *
 * Why a second tree exists at all. The VM builds a brand new VeraUiNode tree on
 * every frame, and ArkUI does not re-render a component because an object was
 * *replaced* -- only because one was *mutated*. Three approaches were each built
 * and measured on device before this one, and all three left the screen stale
 * while the VM ran correctly underneath: passing the node to a nested @Builder,
 * keying ForEach on node content, and a recursive @Component taking the node as
 * @Prop. So the renderer keeps a persistent tree of @Trace'd nodes and copies
 * each new frame into it field by field. Mutation propagates; replacement does
 * not.
 *
 * Why not simply mark VeraUiNode itself observable: decodeVeraUi is a measured
 * phase of the benchmark (decodeUs, part of coldTotalUs), and putting
 * observation overhead inside it would move a published number. Decode stays a
 * cheap pure function producing plain data; the cost of observation lands here,
 * in the renderer, where buildUs already accounts for it.
 */

import { VeraUiNode } from '../vera/VeraUi'

@ObservedV2
export class LiveNode {
  @Trace kind: string = ''
  @Trace style: string = ''
  @Trace text: string = ''
  @Trace source: string = ''
  @Trace alt: string = ''
  @Trace action: string = ''
  @Trace eventValue: number = 0
  @Trace enabled: boolean = true
  @Trace commands: string = ''
  @Trace spinPeriodMs: number = 0
  @Trace label: string = ''
  @Trace tickerId: string = ''
  @Trace columns: number = 1
  @Trace value: string = ''
  @Trace checked: boolean = false
  @Trace minimum: number = 0
  @Trace maximum: number = 100
  @Trace options: string[] = []
  // The typed numeric layer; see VeraUiNode.
  @Trace intValue: number = 0
  @Trace prefix: string = ''
  @Trace suffix: string = ''
  @Trace minimumDigits: number = 1
  @Trace icon: string = ''
  @Trace children: LiveNode[] = []
}

/** A fresh live subtree, used for the parts a frame actually adds. */
export function toLive(node: VeraUiNode): LiveNode {
  let live = new LiveNode()
  live.kind = node.kind
  live.style = node.style
  live.text = node.text
  live.source = node.source
  live.alt = node.alt
  live.action = node.action
  live.eventValue = node.eventValue
  live.enabled = node.enabled
  live.commands = node.commands
  live.spinPeriodMs = node.spinPeriodMs
  live.label = node.label
  live.tickerId = node.tickerId
  live.columns = node.columns
  live.value = node.value
  live.checked = node.checked
  live.minimum = node.minimum
  live.maximum = node.maximum
  live.options = node.options
  live.intValue = node.intValue
  live.prefix = node.prefix
  live.suffix = node.suffix
  live.minimumDigits = node.minimumDigits
  live.icon = node.icon
  let kids: LiveNode[] = []
  for (let child of node.children) { kids.push(toLive(child)) }
  live.children = kids
  return live
}

/**
 * Copy one frame into the live tree, touching only what differs.
 *
 * Assigning a @Trace field notifies every component that reads it, so the
 * comparisons are not an optimisation -- writing an unchanged value would
 * re-render a node that did not change, which is the very behaviour this
 * replaces.
 *
 * Children are matched by position, and a position that already exists keeps
 * its node. That is not an optimisation either -- it is the invariant the
 * renderer depends on. ForEach there is keyed by position, so ArkUI retains the
 * component it already built for that key and never re-invokes the builder; the
 * component goes on reading the LiveNode it closed over. Hand it a replacement
 * object and that row freezes forever at whatever it showed when it was
 * created, while the new node is rendered by nobody.
 *
 * Rebuilding the whole list whenever the count changed did exactly that, and it
 * is the common case rather than a rare one: any program that appends to a log
 * grows its list every frame. A list drawn newest-first -- the natural way to
 * show a journal -- then disagrees with its own state on every row.
 */
export function reconcile(live: LiveNode, next: VeraUiNode): void {
  if (live.kind !== next.kind) { live.kind = next.kind }
  if (live.style !== next.style) { live.style = next.style }
  if (live.text !== next.text) { live.text = next.text }
  if (live.source !== next.source) { live.source = next.source }
  if (live.alt !== next.alt) { live.alt = next.alt }
  if (live.action !== next.action) { live.action = next.action }
  if (live.eventValue !== next.eventValue) { live.eventValue = next.eventValue }
  if (live.enabled !== next.enabled) { live.enabled = next.enabled }
  if (live.commands !== next.commands) { live.commands = next.commands }
  if (live.spinPeriodMs !== next.spinPeriodMs) { live.spinPeriodMs = next.spinPeriodMs }
  if (live.label !== next.label) { live.label = next.label }
  if (live.tickerId !== next.tickerId) { live.tickerId = next.tickerId }
  if (live.columns !== next.columns) { live.columns = next.columns }
  if (live.value !== next.value) { live.value = next.value }
  if (live.checked !== next.checked) { live.checked = next.checked }
  if (live.minimum !== next.minimum) { live.minimum = next.minimum }
  if (live.maximum !== next.maximum) { live.maximum = next.maximum }
  if (live.options.join('\u0000') !== next.options.join('\u0000')) { live.options = next.options }
  if (live.intValue !== next.intValue) { live.intValue = next.intValue }
  if (live.prefix !== next.prefix) { live.prefix = next.prefix }
  if (live.suffix !== next.suffix) { live.suffix = next.suffix }
  if (live.minimumDigits !== next.minimumDigits) { live.minimumDigits = next.minimumDigits }
  if (live.icon !== next.icon) { live.icon = next.icon }

  // Reconcile the positions that already exist, in place, so the components
  // rendering them keep pointing at a node that is still being updated.
  let shared = live.children.length < next.children.length
    ? live.children.length : next.children.length
  for (let i = 0; i < shared; i++) {
    reconcile(live.children[i], next.children[i])
  }
  if (live.children.length === next.children.length) { return }

  // The length did change, so the array has to be reassigned -- @Trace sees a
  // field being written, not an array being mutated, and without the write
  // ForEach never learns the list grew. The surviving nodes are carried over
  // by reference; only the tail is new.
  let kids: LiveNode[] = []
  for (let i = 0; i < shared; i++) { kids.push(live.children[i]) }
  for (let i = shared; i < next.children.length; i++) { kids.push(toLive(next.children[i])) }
  live.children = kids
}
