// What a chat widget is built from (VeraChat.ets): the agent and the blocks read the one request, in the same order of preference,
// and a revision is built by neither.
'use strict'
const assert = require('node:assert/strict')
const {loadVera} = require('./source-loader')
const chat = loadVera('VeraChat')
const {WidgetBuildContext} = loadVera('VeraWidgetContext')
const {settings} = loadVera('SettingsStore')
const compose = loadVera('VeraCompose')

settings.hasSelectorKey = () => true
const context = fields => Object.assign(new WidgetBuildContext(), fields)
const both = c => ({agent: chat.chatAgentRequest(c) && chat.chatAgentRequest(c).prompt, blocks: chat.chatBlocksPrompt(c)})

// The marker's plain request first, then the description, then the message: for both.
assert.deepEqual(both(context({request: ' tip calculator ', brief: 'a long description', currentRequest: 'the message'})), {agent: 'tip calculator', blocks: 'tip calculator'})
assert.deepEqual(both(context({request: '', brief: 'a long description', currentRequest: 'the message'})), {agent: 'a long description', blocks: 'a long description'})
assert.deepEqual(both(context({request: '  ', brief: ' ', currentRequest: ' the message '})), {agent: 'the message', blocks: 'the message'})
// A revision of an existing widget is no replacement to build.
assert.equal(chat.chatBlocksPrompt(context({request: 'tip calculator', source: 'import ...'})), '')
assert.equal(chat.chatAgentRequest(context({request: 'tip calculator', source: 'import ...'})), null)
// A widget built on search results is not the agent's (the blocks are asked by the page, which checks the same source).
assert.equal(chat.chatAgentRequest(context({request: 'weather', verifiedSearchResults: ['x']})), null)
assert.equal(chat.chatBlocksPrompt(context({request: 'weather', verifiedSearchResults: ['x']})), 'weather')
assert.equal(chat.chatAgentRequest(context({request: 'tip calculator'})).widget, true)
console.log('chat-prompt-check: ok')
