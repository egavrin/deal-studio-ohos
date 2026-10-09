// Mirrors VeraPreview.ets's textFieldIssue() exactly, so its logic is
// confirmed on the host before it ever touches ArkUI (Units 8-10).
function textFieldIssue(node) {
  const v = node.value
  if (node.required && v.length === 0) {
    return node.requiredMessage.length > 0 ? node.requiredMessage : 'Required'
  }
  if (v.length === 0) { return '' }
  if (node.minLength > 0 && v.length < node.minLength) {
    return node.minLengthMessage.length > 0 ? node.minLengthMessage
      : 'Enter at least ' + node.minLength.toString() + ' characters'
  }
  if (node.maxLength >= 0 && v.length > node.maxLength) {
    return node.maxLengthMessage.length > 0 ? node.maxLengthMessage
      : 'Enter at most ' + node.maxLength.toString() + ' characters'
  }
  if (node.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v)) {
    return node.emailMessage.length > 0 ? node.emailMessage : 'Enter a valid email address'
  }
  if (node.pattern.length > 0 && !new RegExp(node.pattern).test(v)) {
    return node.patternMessage.length > 0 ? node.patternMessage : 'Invalid format'
  }
  return ''
}

function base(overrides) {
  return Object.assign({
    value: '', required: false, requiredMessage: '',
    minLength: 0, minLengthMessage: '', maxLength: -1, maxLengthMessage: '',
    pattern: '', patternMessage: '', email: false, emailMessage: '',
  }, overrides)
}

const cases = [
  [base({ required: true }), 'Required'],
  [base({ required: true, requiredMessage: 'We need your email' }), 'We need your email'],
  [base({ required: true, value: 'x' }), ''],
  [base({ minLength: 4, value: 'abc' }), 'Enter at least 4 characters'],
  [base({ minLength: 4, value: 'abcd' }), ''],
  [base({ maxLength: 3, value: 'abcd' }), 'Enter at most 3 characters'],
  [base({ maxLength: 3, value: 'abc' }), ''],
  [base({ maxLength: 0, value: 'a' }), 'Enter at most 0 characters'],
  [base({ maxLength: 0, value: '' }), ''],
  [base({ email: true, value: 'not-an-email' }), 'Enter a valid email address'],
  [base({ email: true, value: 'a@b.com' }), ''],
  [base({ pattern: '^[0-9]+$', value: 'abc' }), 'Invalid format'],
  [base({ pattern: '^[0-9]+$', value: '123' }), ''],
  [base({ pattern: '^[0-9]+$', patternMessage: 'Digits only', value: 'abc' }), 'Digits only'],
]

let failed = 0
for (const [node, want] of cases) {
  const got = textFieldIssue(node)
  const ok = got === want
  if (!ok) failed++
  console.log((ok ? 'ok  ' : 'FAIL') + '  value=' + JSON.stringify(node.value) + '  -> ' + JSON.stringify(got) + (ok ? '' : '  want ' + JSON.stringify(want)))
}
process.exit(failed > 0 ? 1 : 0)
