import { Instruction, BytecodeFunction, BytecodeModule } from './VeraInterpreter'
import { CATALOG, ComponentSpec, ChildRule, stylesFor, payloadKindFor, childRuleFor, listWords } from './VeraUiCatalog'
import { iconPath, iconNames } from './VeraIcons'
import { INTENT_CATALOG, intentByName } from './VeraIntentCatalog'
import { IntentParam } from './VeraIntentCatalog'
import { CALENDAR_CATALOG, calendarFnByName } from './VeraCalendarCatalog'

// ===== AST Nodes =====

class Position {
  offset: number
  line: number
  column: number
  constructor(offset: number, line: number, column: number) {
    this.offset = offset; this.line = line; this.column = column
  }
}

class Span {
  start: Position
  end: Position
  sourceName: string
  constructor(start: Position, end: Position, sourceName: string) {
    this.start = start; this.end = end; this.sourceName = sourceName
  }
}

abstract class Node {
  span: Span
  constructor(span: Span) { this.span = span }
}

class TypeNode extends Node {
  name: string
  parts: TypeNode[]
  nullable: boolean
  constructor(span: Span, name: string, parts: TypeNode[] = [], nullable: boolean = false) {
    super(span); this.name = name; this.parts = parts; this.nullable = nullable
  }
}

class Parameter extends Node {
  name: string
  type: TypeNode
  constructor(span: Span, name: string, type: TypeNode) {
    super(span); this.name = name; this.type = type
  }
}

abstract class Declaration extends Node {}

class ImportDeclaration extends Node {
  name: string
  specifier: string
  constructor(span: Span, name: string, specifier: string) {
    super(span); this.name = name; this.specifier = specifier
  }
}

class FunctionDeclaration extends Declaration {
  name: string
  parameters: Parameter[]
  returnType: TypeNode
  body: BlockStatement
  isAsync: boolean
  constructor(span: Span, name: string, parameters: Parameter[], returnType: TypeNode, body: BlockStatement, isAsync: boolean) {
    super(span); this.name = name; this.parameters = parameters; this.returnType = returnType; this.body = body; this.isAsync = isAsync
  }
}

class FieldDeclaration extends Node {
  name: string
  type: TypeNode
  constructor(span: Span, name: string, type: TypeNode) {
    super(span); this.name = name; this.type = type
  }
}

class ClassDeclaration extends Declaration {
  name: string
  fields: FieldDeclaration[]
  annotation: string | null
  constructor(span: Span, name: string, fields: FieldDeclaration[], annotation: string | null) {
    super(span); this.name = name; this.fields = fields; this.annotation = annotation
  }
}

class Application extends Node {
  imports: ImportDeclaration[]
  declarations: Declaration[]
  constructor(span: Span, imports: ImportDeclaration[], declarations: Declaration[]) {
    super(span); this.imports = imports; this.declarations = declarations
  }
}

abstract class Statement extends Node {}

class BlockStatement extends Statement {
  statements: Statement[]
  constructor(span: Span, statements: Statement[]) {
    super(span); this.statements = statements
  }
}

class LetStatement extends Statement {
  name: string
  type: TypeNode
  initializer: Expression
  constructor(span: Span, name: string, type: TypeNode, initializer: Expression) {
    super(span); this.name = name; this.type = type; this.initializer = initializer
  }
}

class IfStatement extends Statement {
  condition: Expression
  thenBranch: BlockStatement
  elseBranch: Statement | null
  constructor(span: Span, condition: Expression, thenBranch: BlockStatement, elseBranch: Statement | null) {
    super(span); this.condition = condition; this.thenBranch = thenBranch; this.elseBranch = elseBranch
  }
}

class WhileStatement extends Statement {
  condition: Expression
  body: BlockStatement
  constructor(span: Span, condition: Expression, body: BlockStatement) {
    super(span); this.condition = condition; this.body = body
  }
}

class ForOfStatement extends Statement {
  name: string
  type: TypeNode
  iterable: Expression
  body: BlockStatement
  constructor(span: Span, name: string, type: TypeNode, iterable: Expression, body: BlockStatement) {
    super(span); this.name = name; this.type = type; this.iterable = iterable; this.body = body
  }
}

class BreakStatement extends Statement {}
class ContinueStatement extends Statement {}

class ReturnStatement extends Statement {
  value: Expression | null
  constructor(span: Span, value: Expression | null) {
    super(span); this.value = value
  }
}

class AssignStatement extends Statement {
  target: Expression
  value: Expression
  constructor(span: Span, target: Expression, value: Expression) {
    super(span); this.target = target; this.value = value
  }
}

class ExpressionStatement extends Statement {
  expression: Expression
  constructor(span: Span, expression: Expression) {
    super(span); this.expression = expression
  }
}

class TryStatement extends Statement {
  tryBlock: BlockStatement
  catchName: string
  catchBlock: BlockStatement
  constructor(span: Span, tryBlock: BlockStatement, catchName: string, catchBlock: BlockStatement) {
    super(span); this.tryBlock = tryBlock; this.catchName = catchName; this.catchBlock = catchBlock
  }
}

abstract class Expression extends Node {}

class NameExpression extends Expression {
  name: string
  constructor(span: Span, name: string) { super(span); this.name = name }
}

class IntExpression extends Expression {
  value: number
  constructor(span: Span, value: number) { super(span); this.value = value }
}

class NumberExpression extends Expression {
  value: number
  constructor(span: Span, value: number) { super(span); this.value = value }
}

class StringExpression extends Expression {
  value: string
  constructor(span: Span, value: string) { super(span); this.value = value }
}

class BooleanExpression extends Expression {
  value: boolean
  constructor(span: Span, value: boolean) { super(span); this.value = value }
}

class NullExpression extends Expression {}

class UnaryExpression extends Expression {
  operator: string
  operand: Expression
  constructor(span: Span, operator: string, operand: Expression) {
    super(span); this.operator = operator; this.operand = operand
  }
}

class BinaryExpression extends Expression {
  left: Expression
  operator: string
  right: Expression
  constructor(span: Span, left: Expression, operator: string, right: Expression) {
    super(span); this.left = left; this.operator = operator; this.right = right
  }
}

class CallExpression extends Expression {
  callee: Expression
  argumentsList: Expression[]
  constructor(span: Span, callee: Expression, argumentsList: Expression[]) {
    super(span); this.callee = callee; this.argumentsList = argumentsList
  }
}

class IndexExpression extends Expression {
  target: Expression
  index: Expression
  constructor(span: Span, target: Expression, index: Expression) {
    super(span); this.target = target; this.index = index
  }
}

class SelectExpression extends Expression {
  target: Expression
  field: string
  constructor(span: Span, target: Expression, field: string) {
    super(span); this.target = target; this.field = field
  }
}

class ArrayExpression extends Expression {
  elements: Expression[]
  constructor(span: Span, elements: Expression[]) {
    super(span); this.elements = elements
  }
}

class Property extends Node {
  name: string
  value: Expression
  constructor(span: Span, name: string, value: Expression) {
    super(span); this.name = name; this.value = value
  }
}

class ObjectExpression extends Expression {
  properties: Property[]
  constructor(span: Span, properties: Property[]) {
    super(span); this.properties = properties
  }
}

class LambdaExpression extends Expression {
  parameters: Parameter[]
  returnType: TypeNode
  body: BlockStatement
  constructor(span: Span, parameters: Parameter[], returnType: TypeNode, body: BlockStatement) {
    super(span); this.parameters = parameters; this.returnType = returnType; this.body = body
  }
}

class AwaitExpression extends Expression {
  operand: Expression
  constructor(span: Span, operand: Expression) { super(span); this.operand = operand }
}

class EnsureNotNullExpression extends Expression {
  operand: Expression
  constructor(span: Span, operand: Expression) { super(span); this.operand = operand }
}

// ===== Type System =====

abstract class VeraType {
  abstract display(): string
}

class PrimitiveType extends VeraType {
  name: string
  constructor(name: string) { super(); this.name = name }
  display(): string { return this.name }
}

class VeraClassType extends VeraType {
  identity: string
  name: string
  fields: Map<string, VeraType> = new Map<string, VeraType>()
  constructor(identity: string, name: string) { super(); this.identity = identity; this.name = name }
  display(): string { return this.name }
}

class VeraArrayType extends VeraType {
  element: VeraType
  constructor(element: VeraType) { super(); this.element = element }
  display(): string { return this.element.display() + '[]' }
}

class NullableType extends VeraType {
  base: VeraType
  constructor(base: VeraType) { super(); this.base = base }
  display(): string { return '(' + this.base.display() + ' | null)' }
}

class VeraFunctionType extends VeraType {
  parameters: VeraType[]
  result: VeraType
  isAsync: boolean
  identity: string
  /** See ExternalFunction.required; equal to parameters.length for everything else. */
  required: number
  constructor(parameters: VeraType[], result: VeraType, isAsync: boolean, identity: string,
      required: number = -1) {
    super(); this.parameters = parameters; this.result = result; this.isAsync = isAsync; this.identity = identity
    this.required = required < 0 ? parameters.length : required
  }
  display(): string {
    let parts: string[] = []
    for (let i = 0; i < this.parameters.length; i++) { parts.push(this.parameters[i].display()) }
    return 'function (' + parts.join(', ') + '): ' + this.result.display()
  }
}

class NamespaceType extends VeraType {
  name: string
  members: Map<string, VeraType>
  constructor(name: string, members: Map<string, VeraType>) { super(); this.name = name; this.members = members }
  display(): string { return 'namespace ' + this.name }
}

class VeraNullType extends VeraType {
  display(): string { return 'null' }
}

const INT = new PrimitiveType('int')
const NUMBER = new PrimitiveType('number')
const BOOLEAN = new PrimitiveType('boolean')
const STRING = new PrimitiveType('string')
const VOID = new PrimitiveType('void')
const NULL_TYPE = new VeraNullType()

function identical(left: VeraType, right: VeraType): boolean {
  if (left === right) return true
  if (left instanceof VeraArrayType && right instanceof VeraArrayType) return identical(left.element, right.element)
  if (left instanceof NullableType && right instanceof NullableType) return identical(left.base, right.base)
  if (left instanceof VeraFunctionType && right instanceof VeraFunctionType) {
    if (left.isAsync !== right.isAsync) return false
    if (left.parameters.length !== right.parameters.length) return false
    for (let i = 0; i < left.parameters.length; i++) {
      if (!identical(left.parameters[i], right.parameters[i])) return false
    }
    return identical(left.result, right.result)
  }
  return false
}

function subtypeOf(source: VeraType, destination: VeraType): boolean {
  if (identical(source, destination)) return true
  if (destination instanceof NullableType && (subtypeOf(source, destination.base) || source instanceof VeraNullType)) return true
  if (source instanceof VeraFunctionType && destination instanceof VeraFunctionType) {
    if (source.isAsync !== destination.isAsync) return false
    if (source.parameters.length > destination.parameters.length) return false
    for (let i = 0; i < source.parameters.length; i++) {
      if (!subtypeOf(destination.parameters[i], source.parameters[i])) return false
    }
    return subtypeOf(source.result, destination.result)
  }
  return false
}

function assignable(source: VeraType, destination: VeraType): boolean {
  return subtypeOf(source, destination)
}

// ===== Lexer =====

export class Diagnostic {
  code: string
  message: string
  span: Span
  expected: string
  actual: string
  constructor(code: string, message: string, span: Span, expected: string = '', actual: string = '') {
    this.code = code; this.message = message; this.span = span; this.expected = expected; this.actual = actual
  }
}

export class CompileError extends Error {
  diagnostics: Diagnostic[]
  constructor(diagnostics: Diagnostic[]) {
    let msgs: string[] = []
    for (let d of diagnostics) {
      msgs.push(d.span.start.line + ':' + d.span.start.column + ' ' + d.code + ' ' + d.message)
    }
    super(msgs.join('\n'))
    this.diagnostics = diagnostics
  }
}

class Token {
  kind: string
  text: string
  span: Span
  constructor(kind: string, text: string, span: Span) {
    this.kind = kind; this.text = text; this.span = span
  }
}

const KEYWORDS: string[] = [
  'import', 'as', 'from', 'class', 'function', 'async', 'let', 'if', 'else',
  'while', 'for', 'of', 'break', 'continue', 'return', 'true', 'false', 'null',
  'try', 'catch', 'new'
]

function isAlpha(c: string): boolean {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c === '_'
}

function isDigit(c: string): boolean {
  return c >= '0' && c <= '9'
}

function isAlnum(c: string): boolean {
  return isAlpha(c) || isDigit(c)
}

class Lexer {
  private source: string
  private sourceName: string
  private pos: number = 0
  private line: number = 1
  private col: number = 1

  constructor(source: string, sourceName: string) {
    this.source = source; this.sourceName = sourceName
  }

  scan(): Token[] {
    let tokens: Token[] = []
    while (this.pos < this.source.length) {
      this.skipWhitespaceAndComments()
      if (this.pos >= this.source.length) break
      let start = this.makePos()
      let c = this.source[this.pos]
      if (isAlpha(c)) { tokens.push(this.scanIdentifier(start)); continue }
      if (isDigit(c)) { tokens.push(this.scanNumber(start)); continue }
      if (c === '"') { tokens.push(this.scanString(start)); continue }
      if (c === '@') { this.pos++; this.col++; tokens.push(this.scanIdentifier(start)); tokens[tokens.length - 1].kind = 'annotation'; continue }
      tokens.push(this.scanSymbol(start))
    }
    tokens.push(new Token('eof', '', this.makeSpan(this.makePos())))
    return tokens
  }

  private skipWhitespaceAndComments(): void {
    while (this.pos < this.source.length) {
      let c = this.source[this.pos]
      if (c === ' ' || c === '\t' || c === '\r') { this.pos++; this.col++; continue }
      if (c === '\n') { this.pos++; this.line++; this.col = 1; continue }
      if (c === '/' && this.pos + 1 < this.source.length && this.source[this.pos + 1] === '/') {
        while (this.pos < this.source.length && this.source[this.pos] !== '\n') { this.pos++; this.col++ }
        continue
      }
      break
    }
  }

  private scanIdentifier(start: Position): Token {
    let begin = this.pos
    while (this.pos < this.source.length && isAlnum(this.source[this.pos])) { this.pos++; this.col++ }
    let text = this.source.substring(begin, this.pos)
    let kind = 'name'
    if (text === 'true' || text === 'false') kind = 'boolean'
    else if (text === 'null') kind = 'null'
    else {
      for (let kw of KEYWORDS) { if (kw === text) { kind = text; break } }
    }
    return new Token(kind, text, this.makeSpan(start))
  }

  private scanNumber(start: Position): Token {
    let begin = this.pos
    while (this.pos < this.source.length && isDigit(this.source[this.pos])) { this.pos++; this.col++ }
    if (this.pos < this.source.length && this.source[this.pos] === '.' && this.pos + 1 < this.source.length && isDigit(this.source[this.pos + 1])) {
      this.pos++; this.col++
      while (this.pos < this.source.length && isDigit(this.source[this.pos])) { this.pos++; this.col++ }
      return new Token('number', this.source.substring(begin, this.pos), this.makeSpan(start))
    }
    return new Token('integer', this.source.substring(begin, this.pos), this.makeSpan(start))
  }

  private scanString(start: Position): Token {
    this.pos++; this.col++
    let value = ''
    while (this.pos < this.source.length && this.source[this.pos] !== '"') {
      if (this.source[this.pos] === '\\') {
        this.pos++; this.col++
        if (this.pos >= this.source.length) break
        let esc = this.source[this.pos]
        if (esc === 'n') value += '\n'
        else if (esc === 't') value += '\t'
        else if (esc === '\\') value += '\\'
        else if (esc === '"') value += '"'
        else value += esc
        this.pos++; this.col++
      } else {
        if (this.source[this.pos] === '\n') { this.line++; this.col = 0 }
        value += this.source[this.pos]
        this.pos++; this.col++
      }
    }
    if (this.pos < this.source.length) { this.pos++; this.col++ }
    return new Token('string', value, this.makeSpan(start))
  }

  private scanSymbol(start: Position): Token {
    let c = this.source[this.pos]
    this.pos++; this.col++
    if (this.pos < this.source.length) {
      let c2 = c + this.source[this.pos]
      if (c2 === '==') {
        this.pos++; this.col++
        if (this.pos < this.source.length && this.source[this.pos] === '=') {
          this.pos++; this.col++
          return new Token('===', '===', this.makeSpan(start))
        }
        return new Token('==', '==', this.makeSpan(start))
      }
      if (c2 === '!=') {
        this.pos++; this.col++
        if (this.pos < this.source.length && this.source[this.pos] === '=') {
          this.pos++; this.col++
          return new Token('!==', '!==', this.makeSpan(start))
        }
        return new Token('!=', '!=', this.makeSpan(start))
      }
      if (c2 === '&&' || c2 === '||' || c2 === '<=' || c2 === '>=') {
        this.pos++; this.col++
        return new Token(c2, c2, this.makeSpan(start))
      }
    }
    return new Token(c, c, this.makeSpan(start))
  }

  private makePos(): Position { return new Position(this.pos, this.line, this.col) }
  private makeSpan(start: Position): Span { return new Span(start, this.makePos(), this.sourceName) }
}

// ===== Parser =====

class Parser {
  private tokens: Token[]
  private pos: number = 0
  private sourceName: string

  constructor(source: string, sourceName: string) {
    this.sourceName = sourceName
    this.tokens = new Lexer(source, sourceName).scan()
  }

  parse(): Application {
    let start = this.current().span
    let imports: ImportDeclaration[] = []
    let declarations: Declaration[] = []
    while (!this.atEnd()) {
      if (this.check('import')) { imports.push(this.parseImport()); continue }
      if (this.check('annotation')) {
        let ann = this.advance()
        declarations.push(this.parseClass(ann.text))
        continue
      }
      if (this.check('class')) { declarations.push(this.parseClass(null)); continue }
      if (this.check('async')) { declarations.push(this.parseFunction()); continue }
      if (this.check('function')) { declarations.push(this.parseFunction()); continue }
      this.error('expected import, class, or function declaration')
    }
    return new Application(this.span(start), imports, declarations)
  }

  private parseImport(): ImportDeclaration {
    let start = this.current().span
    this.expect('import')
    this.expect('*')
    this.expect('as')
    let name = this.expect('name').text
    this.expect('from')
    let specifier = this.expect('string').text
    return new ImportDeclaration(this.span(start), name, specifier)
  }

  private parseClass(annotation: string | null): ClassDeclaration {
    let start = this.current().span
    this.expect('class')
    let name = this.expect('name').text
    this.expect('{')
    let fields: FieldDeclaration[] = []
    while (!this.check('}') && !this.atEnd()) {
      let fStart = this.current().span
      let fName = this.expect('name').text
      this.expect(':')
      let fType = this.parseType()
      if (this.check(';')) this.advance()
      fields.push(new FieldDeclaration(this.span(fStart), fName, fType))
    }
    this.expect('}')
    return new ClassDeclaration(this.span(start), name, fields, annotation)
  }

  private parseFunction(): FunctionDeclaration {
    let start = this.current().span
    let isAsync = false
    if (this.check('async')) { this.advance(); isAsync = true }
    this.expect('function')
    let name = this.expect('name').text
    this.expect('(')
    let params = this.parseParameters()
    this.expect(')')
    this.expect(':')
    let returnType = this.parseType()
    let body = this.parseBlock()
    return new FunctionDeclaration(this.span(start), name, params, returnType, body, isAsync)
  }

  private parseParameters(): Parameter[] {
    let params: Parameter[] = []
    if (this.check(')')) return params
    while (true) {
      let start = this.current().span
      let name = this.expect('name').text
      this.expect(':')
      let type = this.parseType()
      params.push(new Parameter(this.span(start), name, type))
      if (!this.check(',')) break
      this.advance()
    }
    return params
  }

  private parseType(): TypeNode {
    let start = this.current().span
    let type = this.parseBaseType()
    if (this.check('|')) {
      this.advance()
      this.expect('null')
      type = new TypeNode(this.span(start), type.name, type.parts, true)
    }
    return type
  }

  private parseBaseType(): TypeNode {
    let start = this.current().span
    if (this.check('(')) {
      this.advance()
      let params: TypeNode[] = []
      if (!this.check(')')) {
        while (true) {
          let pStart = this.current().span
          this.expect('name')
          this.expect(':')
          params.push(this.parseType())
          if (!this.check(',')) break
          this.advance()
        }
      }
      this.expect(')')
      this.expect('=')
      this.expect('>')
      let result = this.parseType()
      params.push(result)
      return new TypeNode(this.span(start), 'function', params)
    }
    if (this.check('async')) {
      this.advance()
      this.expect('(')
      let params: TypeNode[] = []
      if (!this.check(')')) {
        while (true) {
          let pStart = this.current().span
          this.expect('name')
          this.expect(':')
          params.push(this.parseType())
          if (!this.check(',')) break
          this.advance()
        }
      }
      this.expect(')')
      this.expect('=')
      this.expect('>')
      let result = this.parseType()
      params.push(result)
      return new TypeNode(this.span(start), 'async-function', params)
    }
    let name = this.expect('name').text
    if (this.check('.')) {
      this.advance()
      let member = this.expect('name').text
      name = name + '.' + member
    }
    if (this.check('[')) {
      this.advance()
      this.expect(']')
      let elementType = new TypeNode(this.span(start), name)
      return new TypeNode(this.span(start), 'array', [elementType])
    }
    return new TypeNode(this.span(start), name)
  }

  private parseBlock(): BlockStatement {
    let start = this.current().span
    this.expect('{')
    let stmts: Statement[] = []
    while (!this.check('}') && !this.atEnd()) {
      stmts.push(this.parseStatement())
    }
    this.expect('}')
    return new BlockStatement(this.span(start), stmts)
  }

  private parseStatement(): Statement {
    if (this.check('let')) return this.parseLet()
    if (this.check('if')) return this.parseIf()
    if (this.check('while')) return this.parseWhile()
    if (this.check('for')) return this.parseFor()
    if (this.check('break')) { let s = this.current().span; this.advance(); if (this.check(';')) this.advance(); return new BreakStatement(this.span(s)) }
    if (this.check('continue')) { let s = this.current().span; this.advance(); if (this.check(';')) this.advance(); return new ContinueStatement(this.span(s)) }
    if (this.check('return')) return this.parseReturn()
    if (this.check('try')) return this.parseTry()
    if (this.check('{')) return this.parseBlock()
    return this.parseExpressionOrAssign()
  }

  private parseLet(): LetStatement {
    let start = this.current().span
    this.expect('let')
    let name = this.expect('name').text
    this.expect(':')
    let type = this.parseType()
    this.expect('=')
    let init = this.parseExpression()
    if (this.check(';')) this.advance()
    return new LetStatement(this.span(start), name, type, init)
  }

  private parseIf(): IfStatement {
    let start = this.current().span
    this.expect('if')
    this.expect('(')
    let condition = this.parseExpression()
    this.expect(')')
    let thenBranch = this.parseBlock()
    let elseBranch: Statement | null = null
    if (this.check('else')) {
      this.advance()
      if (this.check('if')) elseBranch = this.parseIf()
      else elseBranch = this.parseBlock()
    }
    return new IfStatement(this.span(start), condition, thenBranch, elseBranch)
  }

  private parseWhile(): WhileStatement {
    let start = this.current().span
    this.expect('while')
    this.expect('(')
    let condition = this.parseExpression()
    this.expect(')')
    let body = this.parseBlock()
    return new WhileStatement(this.span(start), condition, body)
  }

  private parseFor(): ForOfStatement {
    let start = this.current().span
    this.expect('for')
    this.expect('(')
    this.expect('let')
    let name = this.expect('name').text
    this.expect(':')
    let type = this.parseType()
    this.expect('of')
    let iterable = this.parseExpression()
    this.expect(')')
    let body = this.parseBlock()
    return new ForOfStatement(this.span(start), name, type, iterable, body)
  }

  private parseReturn(): ReturnStatement {
    let start = this.current().span
    this.expect('return')
    let value: Expression | null = null
    if (!this.check('}') && !this.check(';') && !this.atEnd()) {
      value = this.parseExpression()
    }
    if (this.check(';')) this.advance()
    return new ReturnStatement(this.span(start), value)
  }

  private parseTry(): TryStatement {
    let start = this.current().span
    this.expect('try')
    let tryBlock = this.parseBlock()
    this.expect('catch')
    this.expect('(')
    let catchName = this.expect('name').text
    this.expect(')')
    let catchBlock = this.parseBlock()
    return new TryStatement(this.span(start), tryBlock, catchName, catchBlock)
  }

  private parseExpressionOrAssign(): Statement {
    let start = this.current().span
    let expr = this.parseExpression()
    if (this.check('=')) {
      this.advance()
      let value = this.parseExpression()
      if (this.check(';')) this.advance()
      return new AssignStatement(this.span(start), expr, value)
    }
    if (this.check(';')) this.advance()
    return new ExpressionStatement(this.span(start), expr)
  }

  private parseExpression(): Expression {
    return this.parseBinary(0)
  }

  private parseBinary(minPrec: number): Expression {
    let left = this.parseUnary()
    while (true) {
      let op = this.current().kind
      let prec = this.precedence(op)
      if (prec < 0 || prec < minPrec) break
      let start = left.span
      this.advance()
      let right = this.parseBinary(prec + 1)
      left = new BinaryExpression(this.span(start), left, op, right)
    }
    return left
  }

  private precedence(op: string): number {
    if (op === '||') return 1
    if (op === '&&') return 2
    if (op === '===' || op === '!==') return 3
    if (op === '<' || op === '<=' || op === '>' || op === '>=') return 4
    if (op === '+' || op === '-') return 5
    if (op === '*' || op === '/' || op === '%') return 6
    return -1
  }

  private parseUnary(): Expression {
    let start = this.current().span
    if (this.check('-')) {
      this.advance()
      let operand = this.parseUnary()
      return new UnaryExpression(this.span(start), '-', operand)
    }
    if (this.check('!')) {
      this.advance()
      let operand = this.parseUnary()
      return new UnaryExpression(this.span(start), '!', operand)
    }
    if (this.check('await')) {
      this.advance()
      let operand = this.parseUnary()
      return new AwaitExpression(this.span(start), operand)
    }
    return this.parsePostfix()
  }

  private parsePostfix(): Expression {
    let expr = this.parsePrimary()
    while (true) {
      if (this.check('(')) {
        let start = expr.span
        this.advance()
        let args: Expression[] = []
        if (!this.check(')')) {
          while (true) {
            args.push(this.parseExpression())
            if (!this.check(',')) break
            this.advance()
          }
        }
        this.expect(')')
        expr = new CallExpression(this.span(start), expr, args)
      } else if (this.check('[')) {
        let start = expr.span
        this.advance()
        let index = this.parseExpression()
        this.expect(']')
        expr = new IndexExpression(this.span(start), expr, index)
      } else if (this.check('.')) {
        let start = expr.span
        this.advance()
        let field = this.expect('name').text
        expr = new SelectExpression(this.span(start), expr, field)
      } else if (this.check('!')) {
        let start = expr.span
        this.advance()
        expr = new EnsureNotNullExpression(this.span(start), expr)
      } else {
        break
      }
    }
    return expr
  }

  private parsePrimary(): Expression {
    let start = this.current().span
    if (this.check('name')) {
      let name = this.advance().text
      return new NameExpression(this.span(start), name)
    }
    if (this.check('integer')) {
      let text = this.advance().text
      let value = parseInt(text)
      return new IntExpression(this.span(start), value)
    }
    if (this.check('number')) {
      let text = this.advance().text
      let value = parseFloat(text)
      return new NumberExpression(this.span(start), value)
    }
    if (this.check('string')) {
      let text = this.advance().text
      return new StringExpression(this.span(start), text)
    }
    if (this.check('boolean')) {
      let text = this.advance().text
      return new BooleanExpression(this.span(start), text === 'true')
    }
    if (this.check('null')) {
      this.advance()
      return new NullExpression(this.span(start))
    }
    if (this.check('(')) {
      this.advance()
      if (this.check(')') || this.isLambdaStart()) {
        return this.parseLambda(start)
      }
      let expr = this.parseExpression()
      this.expect(')')
      return expr
    }
    if (this.check('[')) {
      this.advance()
      let elements: Expression[] = []
      if (!this.check(']')) {
        while (true) {
          elements.push(this.parseExpression())
          if (!this.check(',')) break
          this.advance()
        }
      }
      this.expect(']')
      return new ArrayExpression(this.span(start), elements)
    }
    if (this.check('{')) {
      this.advance()
      let props: Property[] = []
      if (!this.check('}')) {
        while (true) {
          let pStart = this.current().span
          let pName = this.expect('name').text
          this.expect(':')
          let pValue = this.parseExpression()
          props.push(new Property(this.span(pStart), pName, pValue))
          if (!this.check(',')) break
          this.advance()
        }
      }
      this.expect('}')
      return new ObjectExpression(this.span(start), props)
    }
    this.error('expected expression')
    return new NullExpression(this.span(start))
  }

  private isLambdaStart(): boolean {
    let saved = this.pos
    if (this.check('name')) {
      this.advance()
      let result = this.check(':')
      this.pos = saved
      return result
    }
    this.pos = saved
    return false
  }

  private parseLambda(start: Span): LambdaExpression {
    let params: Parameter[] = []
    if (!this.check(')')) {
      while (true) {
        let pStart = this.current().span
        let pName = this.expect('name').text
        this.expect(':')
        let pType = this.parseType()
        params.push(new Parameter(this.span(pStart), pName, pType))
        if (!this.check(',')) break
        this.advance()
      }
    }
    this.expect(')')
    this.expect(':')
    let returnType = this.parseType()
    this.expect('=')
    this.expect('>')
    let body = this.parseBlock()
    return new LambdaExpression(this.span(start), params, returnType, body)
  }

  private current(): Token { return this.tokens[this.pos] }
  private atEnd(): boolean { return this.current().kind === 'eof' }
  private check(kind: string): boolean { return this.current().kind === kind }
  private advance(): Token { let t = this.current(); this.pos++; return t }
  private expect(kind: string): Token {
    if (!this.check(kind)) this.error('expected ' + kind + ', found ' + this.current().kind)
    return this.advance()
  }
  private span(start: Span): Span { return new Span(start.start, this.tokens[this.pos > 0 ? this.pos - 1 : 0].span.end, this.sourceName) }
  private error(message: string): never {
    let span = this.current().span
    throw new CompileError([new Diagnostic('E1001', message, span)])
  }
}

// ===== Semantic Analysis =====

class ExternalFunction {
  name: string
  parameters: VeraType[]
  result: VeraType
  isAsync: boolean
  /** How many of the parameters must actually be passed; the rest are trailing optionals. */
  required: number
  constructor(name: string, parameters: VeraType[], result: VeraType, isAsync: boolean,
      required: number = -1) {
    this.name = name; this.parameters = parameters; this.result = result; this.isAsync = isAsync
    this.required = required < 0 ? parameters.length : required
  }
}

class ExternalClass {
  name: string
  type: VeraClassType
  constructor(name: string, type: VeraClassType) {
    this.name = name; this.type = type
  }
}

class ModuleInterface {
  specifier: string
  functions: ExternalFunction[]
  classes: ExternalClass[]
  constructor(specifier: string, functions: ExternalFunction[], classes: ExternalClass[]) {
    this.specifier = specifier; this.functions = functions; this.classes = classes
  }
}

/**
 * Generated from VeraUiCatalog, so the signatures the compiler accepts cannot
 * drift from what the host decodes, the renderer draws, and the prompt tells
 * the model about.
 */
function buildStdUiModule(): ModuleInterface {
  let viewType = new VeraClassType('std/ui:View', 'View')
  let viewArray = new VeraArrayType(viewType)
  let fns: ExternalFunction[] = []
  for (let spec of CATALOG) {
    let params: VeraType[] = []
    for (let p of spec.props) {
      if (p.kind === 'int') params.push(INT)
      else if (p.kind === 'boolean') params.push(BOOLEAN)
      else if (p.kind === 'view') params.push(viewType)
      else if (p.kind === 'view[]') params.push(viewArray)
      else if (p.kind === 'string[]') params.push(new VeraArrayType(STRING))
      else params.push(STRING)
    }
    // Trailing optionals may be left off, so a program written against an
    // older version of the catalogue still compiles.
    let required = params.length
    while (required > 0 && spec.props[required - 1].optional) { required -= 1 }
    fns.push(new ExternalFunction(spec.name, params, viewType, false, required))
  }
  fns.push(new ExternalFunction('When', [BOOLEAN, viewType], viewType, false))
  fns.push(new ExternalFunction('intToString', [INT], STRING, false))
  fns.push(new ExternalFunction('numberToString', [NUMBER], STRING, false))
  fns.push(new ExternalFunction('booleanToString', [BOOLEAN], STRING, false))
  return new ModuleInterface('std/ui', fns, [new ExternalClass('View', viewType)])
}

/**
 * The clock. Everything is an int, so nothing here needs the number type or a
 * conversion that does not exist yet.
 *
 * nowSeconds is Unix seconds, which stays inside int32 until 2038 -- milliseconds
 * would be ~1.8e12 and trap immediately on the VM's overflow check.
 *
 * Programs should read the clock in handlers, where the result is stored into
 * state, rather than in view(): view is meant to be a pure function of state,
 * and a clock call there makes the tree differ between two renders of the same
 * state.
 */
/**
 * Arithmetic the language cannot express.
 *
 * Everything is monomorphic, so int and number variants are separate entries --
 * ExternalFunction carries concrete types and there are no generics. The two
 * conversions matter most: without them an int radius and a fractional sine can
 * never meet, which is what keeps parametric graphics and any decimal money out
 * of reach.
 */
function buildStdMathModule(): ModuleInterface {
  let fns: ExternalFunction[] = [
    new ExternalFunction('intToNumber', [INT], NUMBER, false),
    new ExternalFunction('numberToInt', [NUMBER], INT, false),
    new ExternalFunction('pi', [], NUMBER, false),
    new ExternalFunction('sqrt', [NUMBER], NUMBER, false),
    new ExternalFunction('sin', [NUMBER], NUMBER, false),
    new ExternalFunction('cos', [NUMBER], NUMBER, false),
    new ExternalFunction('atan2', [NUMBER, NUMBER], NUMBER, false),
    new ExternalFunction('pow', [NUMBER, NUMBER], NUMBER, false),
    new ExternalFunction('floorToInt', [NUMBER], INT, false),
    new ExternalFunction('roundToInt', [NUMBER], INT, false),
    new ExternalFunction('absInt', [INT], INT, false),
    new ExternalFunction('absNumber', [NUMBER], NUMBER, false),
    new ExternalFunction('minInt', [INT, INT], INT, false),
    new ExternalFunction('maxInt', [INT, INT], INT, false),
    new ExternalFunction('minNumber', [NUMBER, NUMBER], NUMBER, false),
    new ExternalFunction('maxNumber', [NUMBER, NUMBER], NUMBER, false),
    // Deterministic and replayable: the seed lives in the program's state, so a
    // saved game restores to the same sequence. A host random() would not.
    new ExternalFunction('randomStep', [INT], INT, false),
    new ExternalFunction('randomBelow', [INT, INT], INT, false),
  ]
  return new ModuleInterface('std/math', fns, [])
}

function buildStdTimeModule(): ModuleInterface {
  let fns: ExternalFunction[] = [
    new ExternalFunction('nowSeconds', [], INT, false),
    new ExternalFunction('millisOfDay', [], INT, false),
    new ExternalFunction('daysSinceEpoch', [], INT, false),
    new ExternalFunction('hourOfDay', [], INT, false),
    new ExternalFunction('minuteOfHour', [], INT, false),
    new ExternalFunction('weekday', [], INT, false),
    // The calendar fields. daysSinceEpoch answers "same day?" but cannot name a
    // day, so anything a person reads back later -- a history row, a report
    // shown to someone else -- had no way to say which date it was about.
    new ExternalFunction('dayOfMonth', [], INT, false),
    new ExternalFunction('monthOfYear', [], INT, false),
    new ExternalFunction('year', [], INT, false),
  ]
  return new ModuleInterface('std/time', fns, [])
}

/**
 * Text, as specified in VERA-L.md's `std/strings` library.
 *
 * The language itself gives a string only `+`, comparison, `.length()` and
 * for-of over its characters, so until now a program could build text but never
 * take it apart. These are the spec's eight functions, with the spec's
 * semantics rather than ArkTS's -- notably positions are Unicode scalar values,
 * not UTF-16 code units.
 *
 * Note the one inconsistency this introduces: the `.length()` intrinsic counts
 * UTF-16 code units (VeraInterpreter's 'length' op), while for-of over a string
 * and `strings.length` here both count scalar values. They agree on every
 * character in the BMP and disagree on an emoji.
 */
function buildStdStringsModule(): ModuleInterface {
  let fns: ExternalFunction[] = [
    new ExternalFunction('length', [STRING], INT, false),
    new ExternalFunction('substring', [STRING, INT, INT], STRING, false),
    new ExternalFunction('contains', [STRING, STRING], BOOLEAN, false),
    new ExternalFunction('startsWith', [STRING, STRING], BOOLEAN, false),
    new ExternalFunction('endsWith', [STRING, STRING], BOOLEAN, false),
    new ExternalFunction('replace', [STRING, STRING, STRING], STRING, false),
    new ExternalFunction('split', [STRING, STRING], new VeraArrayType(STRING), false),
    new ExternalFunction('trim', [STRING], STRING, false),
  ]
  return new ModuleInterface('std/strings', fns, [])
}

/**
 * The platform's intents, generated from VeraIntentCatalog.
 *
 * Each row yields two names: a class holding the intent's parameters and the
 * function that takes it. A record rather than positional arguments because
 * almost every intent parameter is a string -- swap two of them positionally
 * and the call still compiles and still runs, just wrongly. As fields they are
 * checked: an unknown one is E2022, a missing one E2024.
 *
 * The second argument is the name of the handler the answer comes back to,
 * spelled the way ui.Button spells its action. The result is an int request id,
 * because the call is an effect: the VM is synchronous and the platform is not.
 */
function buildStdIntentModule(): ModuleInterface {
  let fns: ExternalFunction[] = []
  let classes: ExternalClass[] = []
  for (let spec of INTENT_CATALOG) {
    let paramsType = new VeraClassType('std/intent:' + spec.paramsClass, spec.paramsClass)
    for (let p of spec.params) {
      paramsType.fields.set(p.name, p.kind === 'int' ? INT : STRING)
    }
    classes.push(new ExternalClass(spec.paramsClass, paramsType))
    fns.push(new ExternalFunction(spec.name, [paramsType, STRING], INT, false))
  }
  // The way out of the catalogue, for an intent nobody has written a row for.
  //
  // Every row above is a promise: the parameters were read out of a contract
  // and the call was watched working on a phone. This one promises nothing. The
  // program names the target and writes the platform's own parameter keys, and
  // the compiler can check neither -- the phone has 810 intents and 734 of them
  // declare no parameters at all, so there is nothing to check against.
  //
  // It exists because the alternative is worse: a catalogue that will never
  // cover the phone, and a program that cannot even try. The cost is paid at
  // the other end -- the person confirms every one of these before it runs,
  // with the target and the payload in front of them, because nothing else in
  // this system knows whether the call is a volume change or a payment.
  //
  // Parameters are pairs rather than JSON, and that is not a style choice: the
  // first program written against a JSON string built one by concatenation, put
  // a line break in it, and the payload never parsed. The language has no way
  // to escape a string, so asking a program for JSON is asking it to be wrong
  // eventually. Pairs it writes correctly by construction, and the host builds
  // the object -- including a dotted key like "dstLocation.latitude", which
  // nests exactly as a catalogue row's platformName does.
  //
  //   intent.call("com.huawei.hmos.settings/phone_settings/DefaultIntentBackgroundUiAbility/GetSettingSwitch",
  //               ["itemName", "bluetooth"], "background", "onAnswer")
  fns.push(new ExternalFunction('call',
    [STRING, new VeraArrayType(STRING), STRING, STRING], INT, false))
  return new ModuleInterface('std/intent', fns, classes)
}

/**
 * The phone's calendar, generated from VeraCalendarCatalog.
 *
 * Deliberately not an intent: the device's CreateCalendarEvent and its
 * relatives declare no parameters and are not standard intent names, so their
 * contract would have to be invented. Calendar Kit is documented, needs no
 * system signing, and is therefore the better tool -- the same reasoning the
 * intent skill gives for preferring a public API when one exists.
 *
 * One function and one parameter class, shaped exactly like an intent row so
 * the program sees one idiom rather than two.
 */
function buildStdCalendarModule(): ModuleInterface {
  let fns: ExternalFunction[] = []
  let classes: ExternalClass[] = []
  for (let fn of CALENDAR_CATALOG) {
    let paramsType = new VeraClassType('std/calendar:' + fn.paramsClass, fn.paramsClass)
    for (let p of fn.params) {
      paramsType.fields.set(p.name, p.kind === 'int' ? INT : STRING)
    }
    classes.push(new ExternalClass(fn.paramsClass, paramsType))
    fns.push(new ExternalFunction(fn.name, [paramsType, STRING], INT, false))
  }
  return new ModuleInterface('std/calendar', fns, classes)
}

class Scope {
  values: Map<string, VeraType> = new Map<string, VeraType>()
  parent: Scope | null
  constructor(parent: Scope | null) { this.parent = parent }
  find(name: string): VeraType | null {
    let v = this.values.get(name)
    if (v !== undefined) return v
    if (this.parent !== null) return this.parent.find(name)
    return null
  }
}

class SemanticModel {
  expressionTypes: Map<Expression, VeraType> = new Map<Expression, VeraType>()
  declaredTypes: Map<TypeNode, VeraType> = new Map<TypeNode, VeraType>()
  functions: Map<string, VeraFunctionType> = new Map<string, VeraFunctionType>()
  classes: Map<string, VeraClassType> = new Map<string, VeraClassType>()
  imports: Map<string, ModuleInterface> = new Map<string, ModuleInterface>()
  application: Application
  constructor(application: Application) { this.application = application }
}

class Narrowing {
  whenTrue: Scope
  whenFalse: Scope
  constructor(whenTrue: Scope, whenFalse: Scope) { this.whenTrue = whenTrue; this.whenFalse = whenFalse }
}

class Analyzer {
  private diagnostics: Diagnostic[] = []
  private model: SemanticModel
  private globals: Scope = new Scope(null)
  private returnType: VeraType = VOID
  private inAsyncFunction: boolean = false
  private loopDepth: number = 0
  private lambdaCount: number = 0

  constructor(application: Application) {
    this.model = new SemanticModel(application)
  }

  analyze(): SemanticModel {
    this.collectImports()
    for (let decl of this.model.application.declarations) {
      if (!(decl instanceof ClassDeclaration) && !(decl instanceof FunctionDeclaration)) continue
      if (this.globals.find(decl.name) !== null) { this.addError('E2001', 'duplicate global ' + decl.name, decl.span); continue }
      if (decl instanceof ClassDeclaration) {
        let type = new VeraClassType('local:' + decl.name, decl.name)
        this.model.classes.set(decl.name, type)
        this.globals.values.set(decl.name, type)
      } else {
        this.globals.values.set(decl.name, new VeraFunctionType([], VOID, (decl as FunctionDeclaration).isAsync, 'pending:' + decl.name))
      }
    }
    for (let decl of this.model.application.declarations) {
      if (!(decl instanceof FunctionDeclaration)) continue
      let params: VeraType[] = []
      for (let p of decl.parameters) params.push(this.resolveType(p.type))
      let result = this.resolveType(decl.returnType)
      let type = new VeraFunctionType(params, result, decl.isAsync, 'function:' + decl.name)
      this.model.functions.set(decl.name, type)
      this.globals.values.set(decl.name, type)
    }
    for (let decl of this.model.application.declarations) {
      if (decl instanceof ClassDeclaration) this.checkClass(decl)
    }
    this.checkJsonableCycles()
    for (let decl of this.model.application.declarations) {
      if (decl instanceof FunctionDeclaration) this.checkFunction(decl)
    }
    if (this.diagnostics.length > 0) throw new CompileError(this.diagnostics)
    return this.model
  }

  private collectImports(): void {
    // A table rather than a chain of string compares, so a new std module is
    // one entry here plus a host implementation -- nothing in the checker, the
    // code generator, the bytecode format or the VM has to know about it.
    let registry = new Map<string, ModuleInterface>()
    registry.set('std/ui', buildStdUiModule())
    registry.set('std/time', buildStdTimeModule())
    registry.set('std/math', buildStdMathModule())
    registry.set('std/strings', buildStdStringsModule())
    registry.set('std/intent', buildStdIntentModule())
    registry.set('std/calendar', buildStdCalendarModule())
    for (let decl of this.model.application.imports) {
      if (this.globals.find(decl.name) !== null) { this.addError('E2001', 'duplicate global ' + decl.name, decl.span); continue }
      let found = registry.get(decl.specifier)
      let resolved: ModuleInterface | null = found !== undefined ? found : null
      if (resolved === null) { this.addError('E2002', 'module not found: ' + decl.specifier, decl.span); continue }
      let members = new Map<string, VeraType>()
      for (let fn of resolved.functions) members.set(fn.name, new VeraFunctionType(fn.parameters, fn.result, fn.isAsync, 'external:' + resolved.specifier + ':' + fn.name, fn.required))
      for (let cls of resolved.classes) members.set(cls.name, cls.type)
      this.model.imports.set(decl.name, resolved)
      this.globals.values.set(decl.name, new NamespaceType(decl.name, members))
    }
  }

  private checkClass(decl: ClassDeclaration): void {
    let type = this.model.classes.get(decl.name)
    if (type === undefined) return
    if (decl.annotation !== null && decl.annotation !== 'jsonable') this.addError('E2039', 'unknown annotation ' + decl.annotation, decl.span)
    for (let field of decl.fields) {
      if (type.fields.has(field.name)) this.addError('E2003', 'duplicate field ' + field.name, field.span)
      else type.fields.set(field.name, this.resolveType(field.type))
    }
  }

  private checkJsonableCycles(): void {
    let jsonables: ClassDeclaration[] = []
    for (let d of this.model.application.declarations) {
      if (d instanceof ClassDeclaration && d.annotation === 'jsonable') jsonables.push(d)
    }
    let visiting = new Set<string>()
    let visited = new Set<string>()
    let jsonableNames = new Set<string>()
    for (let d of jsonables) jsonableNames.add(d.name)
    for (let d of jsonables) {
      if (this.visitJsonable(d.name, jsonableNames, visiting, visited)) {
        this.addError('E2040', 'circular jsonable dependency involving ' + d.name, d.span)
        break
      }
    }
  }

  private visitJsonable(name: string, jsonable: Set<string>, visiting: Set<string>, visited: Set<string>): boolean {
    if (visiting.has(name)) return true
    if (visited.has(name)) return false
    visiting.add(name)
    let type = this.model.classes.get(name)
    if (type !== undefined) {
      let fieldValues = Array.from(type.fields.values())
      for (let ft of fieldValues) {
        let dep = this.localClass(ft)
        if (dep !== null && jsonable.has(dep.name) && this.visitJsonable(dep.name, jsonable, visiting, visited)) return true
      }
    }
    visiting.delete(name)
    visited.add(name)
    return false
  }

  private localClass(type: VeraType): VeraClassType | null {
    if (type instanceof NullableType) return this.localClass(type.base)
    if (type instanceof VeraArrayType) return this.localClass(type.element)
    if (type instanceof VeraClassType && type.identity.startsWith('local:')) return type
    return null
  }

  private checkFunction(decl: FunctionDeclaration): void {
    let ft = this.model.functions.get(decl.name)
    if (ft === undefined) return
    let prevRet = this.returnType
    let prevAsync = this.inAsyncFunction
    this.returnType = ft.result
    this.inAsyncFunction = decl.isAsync
    let scope = new Scope(this.globals)
    for (let i = 0; i < decl.parameters.length; i++) {
      let p = decl.parameters[i]
      if (scope.find(p.name) !== null) this.addError('E2004', 'declaration ' + p.name + ' shadows a visible entity', p.span)
      else scope.values.set(p.name, ft.parameters[i])
    }
    let returns = this.checkBlock(decl.body, scope)
    if (!identical(this.returnType, VOID) && !returns) this.addError('E2018', 'function ' + decl.name + ' may not return a value', decl.body.span)
    this.returnType = prevRet
    this.inAsyncFunction = prevAsync
  }

  private checkBlock(block: BlockStatement, parent: Scope): boolean {
    let scope = new Scope(parent)
    let returns = false
    for (let s of block.statements) {
      if (this.checkStatement(s, scope)) returns = true
    }
    return returns
  }

  private checkStatement(stmt: Statement, scope: Scope): boolean {
    if (stmt instanceof BlockStatement) return this.checkBlock(stmt, scope)
    if (stmt instanceof LetStatement) {
      let type = this.resolveType(stmt.type)
      this.checkExpression(stmt.initializer, scope, type)
      if (scope.find(stmt.name) !== null) this.addError('E2004', 'declaration ' + stmt.name + ' shadows a visible entity', stmt.span)
      else scope.values.set(stmt.name, type)
      return false
    }
    if (stmt instanceof AssignStatement) {
      let target = this.checkAssignable(stmt.target, scope)
      this.checkExpression(stmt.value, scope, target)
      return false
    }
    if (stmt instanceof ExpressionStatement) {
      this.checkExpression(stmt.expression, scope, null)
      if (!(stmt.expression instanceof CallExpression) && !(stmt.expression instanceof AwaitExpression)) {
        this.addError('E2005', 'expression statement must be a function call', stmt.span)
      }
      return false
    }
    if (stmt instanceof IfStatement) {
      this.requireType(this.checkExpression(stmt.condition, scope, BOOLEAN), BOOLEAN, stmt.condition)
      let narrowing = this.narrow(stmt.condition, scope)
      let thenRet = this.checkBlock(stmt.thenBranch, narrowing.whenTrue)
      let elseRet = stmt.elseBranch === null ? false : this.checkStatement(stmt.elseBranch, narrowing.whenFalse)
      return thenRet && elseRet
    }
    if (stmt instanceof WhileStatement) {
      this.requireType(this.checkExpression(stmt.condition, scope, BOOLEAN), BOOLEAN, stmt.condition)
      this.loopDepth += 1
      this.checkBlock(stmt.body, scope)
      this.loopDepth -= 1
      return false
    }
    if (stmt instanceof ForOfStatement) {
      let iter = this.checkExpression(stmt.iterable, scope, null)
      let declared = this.resolveType(stmt.type)
      let element: VeraType | null = null
      if (iter instanceof VeraArrayType) element = iter.element
      else if (identical(iter, STRING)) element = STRING
      else this.addError('E2006', 'for-of requires an array or string', stmt.iterable.span)
      if (element !== null && !identical(element, declared)) this.typeError(stmt.iterable, declared, element)
      let child = new Scope(scope)
      if (child.find(stmt.name) !== null) this.addError('E2004', 'declaration ' + stmt.name + ' shadows a visible entity', stmt.span)
      else child.values.set(stmt.name, declared)
      this.loopDepth += 1
      this.checkBlock(stmt.body, child)
      this.loopDepth -= 1
      return false
    }
    if (stmt instanceof BreakStatement || stmt instanceof ContinueStatement) {
      if (this.loopDepth === 0) this.addError('E2007', 'loop control used outside a loop', stmt.span)
      return false
    }
    if (stmt instanceof TryStatement) {
      let tryRet = this.checkBlock(stmt.tryBlock, scope)
      let catchScope = new Scope(scope)
      catchScope.values.set(stmt.catchName, STRING)
      let catchRet = this.checkBlock(stmt.catchBlock, catchScope)
      return tryRet && catchRet
    }
    if (stmt instanceof ReturnStatement) {
      if (stmt.value === null) {
        if (!identical(this.returnType, VOID)) this.addError('E2008', 'return value required', stmt.span)
      } else {
        if (identical(this.returnType, VOID)) this.addError('E2009', 'void function cannot return a value', stmt.span)
        else this.checkExpression(stmt.value, scope, this.returnType)
      }
      return true
    }
    return false
  }

  private checkAssignable(expr: Expression, scope: Scope): VeraType {
    if (expr instanceof NameExpression) {
      let type = scope.find(expr.name)
      if (type === null || scope === this.globals || type instanceof VeraFunctionType || type instanceof VeraClassType || type instanceof NamespaceType) {
        this.addError('E2010', 'invalid assignment target', expr.span)
        return VOID
      }
      return type
    }
    if (expr instanceof IndexExpression || expr instanceof SelectExpression) return this.checkExpression(expr, scope, null)
    this.addError('E2010', 'invalid assignment target', expr.span)
    return VOID
  }

  private checkExpression(expr: Expression, scope: Scope, expected: VeraType | null): VeraType {
    let result: VeraType = VOID
    if (expr instanceof IntExpression) {
      if (expr.value > 2147483647) this.addError('E2011', 'integer literal exceeds int32 range', expr.span)
      // `let x: number = 1` used to be a type error, because the lexer only
      // emits a number token when a '.' is present. Writing 1.0 everywhere is a
      // rule no one remembers, and it was a standing source of failed compiles.
      result = (expected !== null && identical(expected, NUMBER)) ? NUMBER : INT
    }
    else if (expr instanceof NumberExpression) result = NUMBER
    else if (expr instanceof StringExpression) result = STRING
    else if (expr instanceof BooleanExpression) result = BOOLEAN
    else if (expr instanceof NullExpression) result = NULL_TYPE
    else if (expr instanceof NameExpression) {
      let found = scope.find(expr.name)
      if (found !== null) result = found
      else { result = VOID; this.addError('E2012', 'unknown name ' + expr.name, expr.span) }
    }
    else if (expr instanceof ArrayExpression) result = this.checkArray(expr, scope, expected)
    else if (expr instanceof ObjectExpression) result = this.checkObject(expr, scope, expected)
    else if (expr instanceof UnaryExpression) result = this.checkUnary(expr, scope)
    else if (expr instanceof BinaryExpression) result = this.checkBinary(expr, scope)
    else if (expr instanceof IndexExpression) {
      let target = this.checkExpression(expr.target, scope, null)
      this.requireType(this.checkExpression(expr.index, scope, INT), INT, expr.index)
      if (target instanceof VeraArrayType) result = target.element
      else this.addError('E2013', 'index target must be an array', expr.target.span)
    }
    else if (expr instanceof SelectExpression) result = this.checkSelect(expr, scope)
    else if (expr instanceof EnsureNotNullExpression) {
      let op = this.checkExpression(expr.operand, scope, null)
      if (op instanceof NullableType) result = op.base
      else { this.addError('E2041', 'ensure-not-null requires a nullable value', expr.span); result = op }
    }
    else if (expr instanceof CallExpression) result = this.checkCall(expr, scope, false)
    else if (expr instanceof AwaitExpression) {
      if (!this.inAsyncFunction) this.addError('E2014', 'await is valid only in an async function', expr.span)
      if (!(expr.operand instanceof CallExpression)) { this.addError('E2015', 'await requires an async function call', expr.span); result = VOID }
      else result = this.checkCall(expr.operand, scope, true)
    }
    else if (expr instanceof LambdaExpression) result = this.checkLambda(expr, scope)
    this.model.expressionTypes.set(expr, result)
    if (expected !== null && !assignable(result, expected)) this.typeError(expr, expected, result)
    return result
  }

  private checkArray(expr: ArrayExpression, scope: Scope, expected: VeraType | null): VeraType {
    let candidate = expected instanceof NullableType ? expected.base : expected
    if (!(candidate instanceof VeraArrayType)) {
      this.addError('E2020', 'array literal requires array context', expr.span)
      return new VeraArrayType(VOID)
    }
    for (let el of expr.elements) this.checkExpression(el, scope, candidate.element)
    return candidate
  }

  private checkObject(expr: ObjectExpression, scope: Scope, expected: VeraType | null): VeraType {
    let candidate = expected instanceof NullableType ? expected.base : expected
    if (!(candidate instanceof VeraClassType)) {
      this.addError('E2021', 'object literal requires class context', expr.span)
      return VOID
    }
    let seen = new Set<string>()
    for (let prop of expr.properties) {
      let field = candidate.fields.get(prop.name)
      if (field === undefined) this.addError('E2022', 'unknown field ' + prop.name, prop.span)
      else this.checkExpression(prop.value, scope, field)
      if (seen.has(prop.name)) this.addError('E2023', 'duplicate property ' + prop.name, prop.span)
      seen.add(prop.name)
    }
    let fieldKeys = Array.from(candidate.fields.keys())
    for (let name of fieldKeys) {
      if (!seen.has(name)) this.addError('E2024', 'missing field ' + name, expr.span)
    }
    return candidate
  }

  private checkUnary(expr: UnaryExpression, scope: Scope): VeraType {
    if (expr.operator === '-' && expr.operand instanceof IntExpression && expr.operand.value === 2147483648) {
      this.model.expressionTypes.set(expr.operand, INT)
      return INT
    }
    let op = this.checkExpression(expr.operand, scope, null)
    if (expr.operator === '!') { this.requireType(op, BOOLEAN, expr.operand); return BOOLEAN }
    if (!identical(op, INT) && !identical(op, NUMBER)) this.addError('E2025', 'unary minus requires int or number', expr.span)
    return op
  }

  private checkBinary(expr: BinaryExpression, scope: Scope): VeraType {
    let left = this.checkExpression(expr.left, scope, null)
    let right = this.checkExpression(expr.right, scope, null)
    let op = expr.operator
    if (op === '===' || op === '!==') {
      let nullPair = this.isNullableNullPair(left, right) || this.isNullableNullPair(right, left)
      let prim = left instanceof PrimitiveType && identical(left, right) && !identical(left, VOID)
      let fns = left instanceof VeraFunctionType && right instanceof VeraFunctionType && (subtypeOf(left, right) || subtypeOf(right, left))
      if (!nullPair && !prim && !fns) this.addError('E2026', 'unsupported equality operands', expr.span)
      return BOOLEAN
    }
    if (op === '&&' || op === '||') {
      this.requireType(left, BOOLEAN, expr.left)
      this.requireType(right, BOOLEAN, expr.right)
      return BOOLEAN
    }
    if (op === '<' || op === '<=' || op === '>' || op === '>=') {
      if ((!identical(left, INT) && !identical(left, NUMBER) && !identical(left, STRING)) || !identical(left, right)) {
        this.addError('E2027', 'relational operands must be equal int, number, or string types', expr.span)
      }
      return BOOLEAN
    }
    if (!identical(left, right)) this.addError('E2028', 'arithmetic operands must have identical types', expr.span)
    let valid = identical(left, INT) || identical(left, NUMBER) || (op === '+' && identical(left, STRING))
    if (!valid || (op === '%' && !identical(left, INT))) this.addError('E2029', 'operator ' + op + ' is invalid for ' + left.display(), expr.span)
    return left
  }

  private checkSelect(expr: SelectExpression, scope: Scope): VeraType {
    let target = this.checkExpression(expr.target, scope, null)
    if (target instanceof NamespaceType) {
      let m = target.members.get(expr.field)
      if (m === undefined) this.addError('E2030', 'namespace has no member ' + expr.field, expr.span)
      return m !== undefined ? m : VOID
    }
    if ((target instanceof VeraArrayType || identical(target, STRING)) && expr.field === 'length') {
      return new VeraFunctionType([], INT, false, 'intrinsic:length')
    }
    // Array growth as intrinsics rather than a std module: the element type
    // comes from the receiver, so these are polymorphic for free, whereas an
    // ExternalFunction carries concrete types and would need one entry per
    // element type -- unbounded, since element types include user classes.
    if (target instanceof VeraArrayType) {
      let element = (target as VeraArrayType).element
      if (expr.field === 'push') {
        // Returns the new length, as in JavaScript. It also has to leave one
        // value behind: every expression statement emits a pop after it.
        return new VeraFunctionType([element], INT, false, 'intrinsic:push')
      }
      if (expr.field === 'pop') {
        return new VeraFunctionType([], element, false, 'intrinsic:pop')
      }
    }
    if (target instanceof VeraClassType) {
      let f = target.fields.get(expr.field)
      if (f === undefined) this.addError('E2031', 'class ' + target.name + ' has no field ' + expr.field, expr.span)
      return f !== undefined ? f : VOID
    }
    if (target instanceof NullableType) this.addError('E2032', 'nullable value must be narrowed before field access', expr.span)
    else this.addError('E2033', 'field selection requires class, array, string, or namespace', expr.span)
    return VOID
  }

  private checkCall(expr: CallExpression, scope: Scope, awaited: boolean): VeraType {
    let callee = this.checkExpression(expr.callee, scope, null)
    if (!(callee instanceof VeraFunctionType)) { this.addError('E2034', 'callee is not a function', expr.callee.span); return VOID }
    if (callee.isAsync !== awaited) this.addError('E2035', callee.isAsync ? 'async call must be awaited' : 'synchronous call cannot be awaited', expr.span)
    if (expr.argumentsList.length < callee.required ||
        expr.argumentsList.length > callee.parameters.length) {
      let want = callee.required === callee.parameters.length
        ? callee.parameters.length.toString()
        : callee.required.toString() + ' to ' + callee.parameters.length.toString()
      this.addError('E2036', 'expected ' + want + ' arguments, found ' +
        expr.argumentsList.length, expr.span)
    }
    for (let i = 0; i < expr.argumentsList.length; i++) {
      let param = i < callee.parameters.length ? callee.parameters[i] : null
      this.checkExpression(expr.argumentsList[i], scope, param)
    }
    this.checkStyleArguments(expr, callee)
    this.checkComposition(expr, callee)
    this.checkIntentArguments(expr, callee)
    return callee.result
  }

  /**
   * The composition rules in VeraUiCatalog's CHILD_RULES, where the source
   * shows enough to check them.
   *
   * These are design rules rather than type rules -- a ListGroup full of Cards
   * type-checks perfectly and draws precisely the thing ListGroup was added to
   * replace. They are caught here and not in the renderer because a compile
   * error is handed back to the model and fixed on the next attempt, while
   * anything the renderer notices is seen only by whoever is watching.
   *
   * Literal children only. A list built by a loop -- which is how every real
   * list is built -- cannot be read here and passes, the same limitation
   * checkStyleArguments has. That is the prompt's half of the job.
   */
  private checkComposition(expr: CallExpression, callee: VeraFunctionType): void {
    const prefix = 'external:std/ui:'
    if (!callee.identity.startsWith(prefix)) return
    let name = callee.identity.substring(prefix.length)
    let rule: ChildRule | null = childRuleFor(name)
    if (rule === null) return

    if (rule!.allowed.length > 0) {
      for (let spec of CATALOG) {
        if (spec.name !== name) continue
        for (let i = 0; i < spec.props.length && i < expr.argumentsList.length; i++) {
          if (spec.props[i].kind !== 'view[]') continue
          let arg = expr.argumentsList[i]
          if (!(arg instanceof ArrayExpression)) break
          for (let element of (arg as ArrayExpression).elements) {
            // Only a child we can positively name is judged. Anything else --
            // a variable, a call that returns a View -- is unknowable here and
            // is left alone rather than guessed at.
            let childName = this.uiComponentName(element)
            if (childName.length === 0) continue
            if (rule!.allowed.indexOf(childName) < 0) {
              this.addError('E2107', name + ' takes only ' + listWords(rule!.allowed) +
                ' children, not ' + childName, element.span)
            }
          }
          break
        }
        break
      }
    }

    for (let bad of rule!.refusedInside) {
      for (let arg of expr.argumentsList) {
        let found = this.findUiDescendant(arg, bad)
        if (found !== null) {
          this.addError('E2107', name + ' may not contain another ' + bad, found!.span)
          break
        }
      }
    }
  }

  /**
   * The std/ui component a literal `ui.Name(...)` names, or '' when the call is
   * not one.
   *
   * Read off the syntax rather than the types, because the arguments have
   * already been checked by the time this runs and checking them again would
   * report every mistake in them twice. The field name alone is enough: a
   * program cannot declare a namespace of its own, and no member of std/time,
   * std/math, std/strings, std/intent or std/calendar shares a name with a
   * component.
   */
  private uiComponentName(expr: Expression): string {
    if (!(expr instanceof CallExpression)) return ''
    let callee = (expr as CallExpression).callee
    if (!(callee instanceof SelectExpression)) return ''
    let field = (callee as SelectExpression).field
    if (field === 'When') return 'When'
    for (let spec of CATALOG) { if (spec.name === field) return field }
    return ''
  }

  /** The first `ui.<name>` call anywhere below this expression, or null. */
  private findUiDescendant(expr: Expression, name: string): Expression | null {
    if (expr instanceof ArrayExpression) {
      for (let element of (expr as ArrayExpression).elements) {
        let found = this.findUiDescendant(element, name)
        if (found !== null) return found
      }
      return null
    }
    if (expr instanceof CallExpression) {
      if (this.uiComponentName(expr) === name) return expr
      for (let arg of (expr as CallExpression).argumentsList) {
        let found = this.findUiDescendant(arg, name)
        if (found !== null) return found
      }
    }
    return null
  }

  /**
   * A style name the renderer does not know silently falls through to its
   * default branch, so the program looks plausible and renders wrong. Catch it
   * where every other mistake is caught.
   *
   * Only literal styles are checked: a computed style is legitimate and cannot
   * be resolved here, so it passes.
   */
  private checkStyleArguments(expr: CallExpression, callee: VeraFunctionType): void {
    const prefix = 'external:std/ui:'
    if (!callee.identity.startsWith(prefix)) return
    let name = callee.identity.substring(prefix.length)
    for (let spec of CATALOG) {
      if (spec.name !== name) continue
      for (let i = 0; i < spec.props.length && i < expr.argumentsList.length; i++) {
        let prop = spec.props[i]
        if (prop.styleSet.length === 0) continue
        let arg = expr.argumentsList[i]
        if (!(arg instanceof StringExpression)) continue
        let allowed = stylesFor(spec.nodeKind)
        if (allowed.length === 0) continue
        if (allowed.indexOf((arg as StringExpression).value) < 0) {
          this.addError('E2105', 'unknown ' + spec.name + ' style "' + (arg as StringExpression).value +
            '"; allowed: ' + allowed.join(' '), arg.span)
        }
      }
      this.checkIconArguments(expr, spec)
      this.checkHandlerSignature(expr, spec)
      return
    }
  }

  /**
   * An icon name outside the set draws nothing, which on screen is
   * indistinguishable from the renderer having failed. Same closed-set
   * treatment as a style, and the same limit: only a literal is checked.
   */
  private checkIconArguments(expr: CallExpression, spec: ComponentSpec): void {
    for (let i = 0; i < spec.props.length && i < expr.argumentsList.length; i++) {
      if (spec.props[i].kind !== 'icon') continue
      let arg = expr.argumentsList[i]
      if (!(arg instanceof StringExpression)) continue
      let value = (arg as StringExpression).value
      // '' is how a component that takes an icon is told not to draw one.
      if (value.length === 0) continue
      if (iconPath(value).length === 0) {
        this.addError('E2108', 'unknown icon "' + value + '"; the icons are: ' +
          iconNames().join(' '), arg.span)
      }
    }
  }

  /**
   * The same idea as checkStyleArguments, for std/intent.
   *
   * checkObject already rejects an unknown or missing field, so what is left is
   * the two things a type cannot say: that a field's value comes from a closed
   * set, and that the result handler exists and takes the answer. Both are
   * caught here rather than at runtime, which matters more than usual -- a
   * compile error goes back into the generation loop and the model fixes it,
   * while a runtime trap surfaces minutes later, on a program that already
   * looked finished.
   *
   * Literal arguments only: a computed record or a computed handler name cannot
   * be resolved here and is left alone.
   */
  private checkIntentArguments(expr: CallExpression, callee: VeraFunctionType): void {
    // Both host-backed modules take (record, handlerName) and both want the
    // same two checks, so they share one implementation. Only the table of
    // field specs differs.
    let label = ''
    let params: IntentParam[] = []
    const intentPrefix = 'external:std/intent:'
    const calendarPrefix = 'external:std/calendar:'
    if (callee.identity === intentPrefix + 'call') {
      this.checkRawIntentArguments(expr)
      return
    }
    if (callee.identity.startsWith(intentPrefix)) {
      let name = callee.identity.substring(intentPrefix.length)
      let spec = intentByName(name)
      if (spec === null) return
      label = 'intent.' + name
      params = spec!.params
    } else if (callee.identity.startsWith(calendarPrefix)) {
      let name = callee.identity.substring(calendarPrefix.length)
      let fn = calendarFnByName(name)
      if (fn === null) return
      label = 'calendar.' + name
      params = fn!.params
    } else {
      return
    }

    if (expr.argumentsList.length > 0 && expr.argumentsList[0] instanceof ObjectExpression) {
      let record = expr.argumentsList[0] as ObjectExpression
      for (let prop of record.properties) {
        if (!(prop.value instanceof StringExpression)) continue
        let value = (prop.value as StringExpression).value
        for (let p of params) {
          if (p.name !== prop.name || p.values.length === 0) continue
          // An empty string is how a record with no optional fields says
          // "omit this parameter", so it is always allowed.
          if (value.length === 0) continue
          if (p.values.indexOf(value) < 0) {
            this.addError('E2105', 'unknown ' + label + ' ' + p.name + ' "' + value +
              '"; allowed: ' + p.values.join(' '), prop.value.span)
          }
        }
      }
    }
    if (expr.argumentsList.length < 2 || !(expr.argumentsList[1] instanceof StringExpression)) return
    let arg = expr.argumentsList[1]
    let handlerName = (arg as StringExpression).value
    let fn = this.model.functions.get(handlerName)
    if (fn === undefined) {
      this.addError('E2106', 'no handler named "' + handlerName + '"', arg.span)
      return
    }
    if (fn.parameters.length < 2 || !identical(fn.parameters[1], STRING)) {
      this.addError('E2106', label + ' answers with a string, so "' +
        handlerName + '" must take (state, value: string)', arg.span)
    }
  }

  /**
   * What little can be checked about intent.call.
   *
   * Not the parameters -- that is the whole point of the escape hatch, and the
   * phone has no contract to check them against. But the shape of the target,
   * the mode and the payload are checkable when they are written out, and each
   * of them is a mistake the model makes and the platform answers with silence:
   * a target with a missing segment goes nowhere, a mode that is not one of the
   * two is ignored, and a payload that is not an object never reaches the
   * target as parameters at all.
   *
   * A computed argument is left alone, as everywhere else here.
   */
  private checkRawIntentArguments(expr: CallExpression): void {
    if (expr.argumentsList.length > 0 && expr.argumentsList[0] instanceof StringExpression) {
      let arg = expr.argumentsList[0]
      let target = (arg as StringExpression).value
      let parts = target.split('/')
      let empty = false
      for (let part of parts) { if (part.trim().length === 0) { empty = true } }
      if (parts.length !== 4 || empty) {
        this.addError('E2109', 'intent.call target must be ' +
          '"bundle/module/ability/IntentName", four parts, none empty; got "' + target + '"', arg.span)
      }
    }
    if (expr.argumentsList.length > 1 && expr.argumentsList[1] instanceof ArrayExpression) {
      let arg = expr.argumentsList[1]
      let items = (arg as ArrayExpression).elements
      if (items.length % 2 !== 0) {
        this.addError('E2109', 'intent.call parameters are name and value in pairs, so the ' +
          'array must have an even number of items; got ' + items.length.toString(), arg.span)
      }
      for (let i = 0; i + 1 < items.length; i = i + 2) {
        if (!(items[i] instanceof StringExpression)) { continue }
        if ((items[i] as StringExpression).value.trim().length === 0) {
          this.addError('E2109', 'intent.call parameter names cannot be empty', items[i].span)
        }
      }
    }
    if (expr.argumentsList.length > 2 && expr.argumentsList[2] instanceof StringExpression) {
      let arg = expr.argumentsList[2]
      let mode = (arg as StringExpression).value
      if (mode !== 'foreground' && mode !== 'background') {
        this.addError('E2109', 'intent.call mode must be "foreground" or "background"; got "' +
          mode + '"', arg.span)
      }
    }
    if (expr.argumentsList.length < 4 || !(expr.argumentsList[3] instanceof StringExpression)) return
    let arg = expr.argumentsList[3]
    let handlerName = (arg as StringExpression).value
    let fn = this.model.functions.get(handlerName)
    if (fn === undefined) {
      this.addError('E2106', 'no handler named "' + handlerName + '"', arg.span)
      return
    }
    if (fn.parameters.length < 2 || !identical(fn.parameters[1], STRING)) {
      this.addError('E2106', 'intent.call answers with a string, so "' + handlerName +
        '" must take (state, value: string)', arg.span)
    }
  }

  /**
   * A component that produces a value hands its handler that value, so the
   * handler's second parameter has to match. Without this the mismatch surfaces
   * as a runtime trap on the first keystroke, long after the program looked
   * finished -- and the retry loop never sees it, because compilation passed.
   *
   * Only a literal handler name is checked; a computed one cannot be resolved
   * here and is left alone.
   */
  private checkHandlerSignature(expr: CallExpression, spec: ComponentSpec): void {
    let payload = payloadKindFor(spec.nodeKind)
    if (payload.length === 0) return
    for (let i = 0; i < spec.props.length && i < expr.argumentsList.length; i++) {
      if (spec.props[i].name !== 'action') continue
      let arg = expr.argumentsList[i]
      if (!(arg instanceof StringExpression)) return
      let handlerName = (arg as StringExpression).value
      let fn = this.model.functions.get(handlerName)
      if (fn === undefined) {
        this.addError('E2106', 'no handler named "' + handlerName + '"', arg.span)
        return
      }
      let want: VeraType = payload === 'string' ? STRING : payload === 'boolean' ? BOOLEAN : INT
      if (fn.parameters.length < 2 || !identical(fn.parameters[1], want)) {
        // "a int" reads as a typo in a message the model is asked to act on.
        let article = payload === 'int' ? 'an ' : 'a '
        this.addError('E2106', spec.name + ' hands its handler ' + article + payload + ', so "' +
          handlerName + '" must take (state, value: ' + payload + ')', arg.span)
      }
      return
    }
  }

  private checkLambda(expr: LambdaExpression, parent: Scope): VeraType {
    let params: VeraType[] = []
    for (let p of expr.parameters) params.push(this.resolveType(p.type))
    let result = this.resolveType(expr.returnType)
    let type = new VeraFunctionType(params, result, false, 'lambda:' + this.lambdaCount++)
    let scope = new Scope(parent)
    for (let i = 0; i < expr.parameters.length; i++) {
      let p = expr.parameters[i]
      if (scope.find(p.name) !== null) this.addError('E2004', 'declaration ' + p.name + ' shadows a visible entity', p.span)
      else scope.values.set(p.name, params[i])
    }
    let oldRet = this.returnType
    let oldAsync = this.inAsyncFunction
    this.returnType = result
    this.inAsyncFunction = false
    let returns = this.checkBlock(expr.body, scope)
    this.returnType = oldRet
    this.inAsyncFunction = oldAsync
    if (!identical(result, VOID) && !returns) this.addError('E2018', 'lambda may not return a value', expr.body.span)
    return type
  }

  private narrow(expr: Expression, scope: Scope): Narrowing {
    let yes = new Scope(scope)
    let no = new Scope(scope)
    if (expr instanceof BinaryExpression) {
      let op = expr.operator
      if (op !== '===' && op !== '!==') return new Narrowing(yes, no)
      let nameExpr: NameExpression | null = null
      if (expr.left instanceof NameExpression && expr.right instanceof NullExpression) nameExpr = expr.left
      else if (expr.right instanceof NameExpression && expr.left instanceof NullExpression) nameExpr = expr.right
      if (nameExpr !== null) {
        let type = scope.find(nameExpr.name)
        if (type !== null && type instanceof NullableType) {
          let narrowedScope = op === '!==' ? yes : no
          narrowedScope.values.set(nameExpr.name, type.base)
        }
      }
    }
    return new Narrowing(yes, no)
  }

  resolveType(node: TypeNode): VeraType {
    let existing = this.model.declaredTypes.get(node)
    if (existing !== undefined) return existing
    let type: VeraType
    if (node.name === 'int') type = INT
    else if (node.name === 'number') type = NUMBER
    else if (node.name === 'boolean') type = BOOLEAN
    else if (node.name === 'string') type = STRING
    else if (node.name === 'void') type = VOID
    else if (node.name === 'array') type = new VeraArrayType(this.resolveType(node.parts[0]))
    else if (node.name === 'function' || node.name === 'async-function') {
      let pieces: VeraType[] = []
      for (let p of node.parts) pieces.push(this.resolveType(p))
      type = new VeraFunctionType(pieces.slice(0, -1), pieces[pieces.length - 1], node.name === 'async-function', 'function-type')
    } else type = this.resolveNamedType(node.name, node)
    if (node.nullable) {
      if (identical(type, VOID)) this.addError('E2037', 'void cannot be nullable', node.span)
      type = new NullableType(type)
    }
    this.model.declaredTypes.set(node, type)
    return type
  }

  private resolveNamedType(name: string, node: TypeNode): VeraType {
    let pieces = name.split('.')
    let value: VeraType | null = this.globals.find(pieces[0])
    for (let i = 1; i < pieces.length; i++) {
      if (value instanceof NamespaceType) {
        let m = value.members.get(pieces[i])
        value = m !== undefined ? m : null
      } else {
        value = null
      }
    }
    if (!(value instanceof VeraClassType)) { this.addError('E2038', 'unknown class type ' + name, node.span); return VOID }
    return value
  }

  private isNullableNullPair(a: VeraType, b: VeraType): boolean {
    return a instanceof NullableType && b instanceof VeraNullType
  }

  private requireType(actual: VeraType, expected: VeraType, expr: Expression): void {
    if (!identical(actual, expected)) this.typeError(expr, expected, actual)
  }

  private typeError(expr: Expression, expected: VeraType, actual: VeraType): void {
    this.diagnostics.push(new Diagnostic('E2019', 'expected ' + expected.display() + ', found ' + actual.display(), expr.span, expected.display(), actual.display()))
  }

  private addError(code: string, message: string, span: Span): void {
    this.diagnostics.push(new Diagnostic(code, message, span))
  }
}

// ===== Bytecode Compilation =====

class Binding {
  location: string
  slot: number
  constructor(location: string, slot: number) { this.location = location; this.slot = slot }
}

class LoopLabels {
  breaks: number[]
  continues: number[]
  continueTarget: number
  constructor(breaks: number[], continues: number[], continueTarget: number) {
    this.breaks = breaks; this.continues = continues; this.continueTarget = continueTarget
  }
}

class FunctionBuilder {
  instructions: Instruction[] = []
  bindings: Map<string, Binding> = new Map<string, Binding>()
  capturedBindings: Map<string, number> = new Map<string, number>()
  loops: LoopLabels[] = []
  localCount: number = 0
  name: string
  parent: FunctionBuilder | null

  constructor(name: string, parent: FunctionBuilder | null) {
    this.name = name; this.parent = parent
  }

  emit(inst: Instruction): number {
    this.instructions.push(inst)
    return this.instructions.length - 1
  }

  local(name: string): number {
    let slot = this.localCount++
    this.bindings.set(name, new Binding('local', slot))
    return slot
  }
}

function mkInst(op: string): Instruction { return new Instruction(op) }

function mkPushInt(v: string): Instruction { let i = mkInst('push-int'); i.value = v; return i }
function mkPushNumber(v: number): Instruction { let i = mkInst('push-number'); i.numValue = v; return i }
function mkPushString(v: string): Instruction { let i = mkInst('push-string'); i.value = v; return i }
function mkPushBoolean(v: boolean): Instruction { let i = mkInst('push-boolean'); i.boolValue = v; return i }
function mkLoadLocal(slot: number): Instruction { let i = mkInst('load-local'); i.slot = slot; return i }
function mkStoreLocal(slot: number): Instruction { let i = mkInst('store-local'); i.slot = slot; return i }
function mkLoadCapture(slot: number): Instruction { let i = mkInst('load-capture'); i.slot = slot; return i }
function mkStoreCapture(slot: number): Instruction { let i = mkInst('store-capture'); i.slot = slot; return i }
function mkLoadFunction(name: string): Instruction { let i = mkInst('load-function'); i.name = name; return i }
function mkLoadExternal(mod: string, name: string): Instruction { let i = mkInst('load-external'); i.module = mod; i.name = name; return i }
function mkUnary(op: string): Instruction { let i = mkInst('unary'); i.operator = op; return i }
function mkBinary(op: string, integer: boolean): Instruction { let i = mkInst('binary'); i.operator = op; i.integer = integer; return i }
function mkJump(target: number): Instruction { let i = mkInst('jump'); i.target = target; return i }
function mkJumpIfFalse(target: number): Instruction { let i = mkInst('jump-if-false'); i.target = target; return i }
function mkCall(count: number, awaited: boolean): Instruction { let i = mkInst('call'); i.count = count; i.awaited = awaited; return i }
function mkMakeArray(count: number): Instruction { let i = mkInst('make-array'); i.count = count; return i }
function mkMakeObject(classIdentity: string, fields: string[]): Instruction {
  let i = mkInst('make-object'); i.classIdentity = classIdentity; i.fields = fields; return i
}
function mkLoadField(name: string): Instruction { let i = mkInst('load-field'); i.name = name; return i }
function mkStoreField(name: string): Instruction { let i = mkInst('store-field'); i.name = name; return i }
function mkMakeClosure(functionName: string, captures: number[]): Instruction {
  let i = mkInst('make-closure'); i.functionName = functionName; i.captures = captures; return i
}

class BytecodeCompiler {
  private functions: BytecodeFunction[] = []
  private lambdaCount: number = 0
  private model: SemanticModel

  constructor(model: SemanticModel) { this.model = model }

  compile(): BytecodeModule {
    for (let decl of this.model.application.declarations) {
      if (decl instanceof FunctionDeclaration) this.compileFunction(decl)
    }
    let entries: string[] = []
    let fnKeys = Array.from(this.model.functions.keys())
    for (let name of fnKeys) entries.push(name)
    return new BytecodeModule(this.functions, entries)
  }

  private compileFunction(decl: FunctionDeclaration): void {
    let b = new FunctionBuilder(decl.name, null)
    for (let p of decl.parameters) b.local(p.name)
    this.block(decl.body, b)
    b.emit(mkInst('push-null'))
    b.emit(mkInst('return'))
    this.functions.push(new BytecodeFunction(decl.name, decl.parameters.length, b.localCount, decl.isAsync, b.instructions))
  }

  private block(block: BlockStatement, b: FunctionBuilder): void {
    for (let s of block.statements) this.statement(s, b)
  }

  private statement(stmt: Statement, b: FunctionBuilder): void {
    if (stmt instanceof BlockStatement) this.block(stmt, b)
    else if (stmt instanceof LetStatement) {
      this.expression(stmt.initializer, b)
      b.emit(mkStoreLocal(b.local(stmt.name)))
    }
    else if (stmt instanceof ExpressionStatement) {
      this.expression(stmt.expression, b)
      b.emit(mkInst('pop'))
    }
    else if (stmt instanceof AssignStatement) this.assignment(stmt, b)
    else if (stmt instanceof ReturnStatement) {
      if (stmt.value === null) b.emit(mkInst('push-null'))
      else this.expression(stmt.value, b)
      b.emit(mkInst('return'))
    }
    else if (stmt instanceof IfStatement) {
      this.expression(stmt.condition, b)
      let falseJump = b.emit(mkJumpIfFalse(-1))
      this.block(stmt.thenBranch, b)
      if (stmt.elseBranch !== null) {
        let endJump = b.emit(mkJump(-1))
        this.patch(b, falseJump, b.instructions.length)
        this.statement(stmt.elseBranch, b)
        this.patch(b, endJump, b.instructions.length)
      } else {
        this.patch(b, falseJump, b.instructions.length)
      }
    }
    else if (stmt instanceof WhileStatement) {
      let start = b.instructions.length
      this.expression(stmt.condition, b)
      let exit = b.emit(mkJumpIfFalse(-1))
      let loop = new LoopLabels([], [], start)
      b.loops.push(loop)
      this.block(stmt.body, b)
      b.emit(mkJump(start))
      let end = b.instructions.length
      this.patch(b, exit, end)
      this.finishLoop(b, loop, end, true)
    }
    else if (stmt instanceof ForOfStatement) this.forOf(stmt, b)
    else if (stmt instanceof TryStatement) {
      this.block(stmt.tryBlock, b)
    }
    else if (stmt instanceof BreakStatement) {
      let loop = b.loops[b.loops.length - 1]
      loop.breaks.push(b.emit(mkJump(-1)))
    }
    else if (stmt instanceof ContinueStatement) {
      let loop = b.loops[b.loops.length - 1]
      loop.continues.push(b.emit(mkJump(-1)))
    }
  }

  private forOf(stmt: ForOfStatement, b: FunctionBuilder): void {
    let arraySlot = b.local('$array' + b.localCount)
    let indexSlot = b.local('$index' + b.localCount)
    let varSlot = b.local(stmt.name)
    this.expression(stmt.iterable, b)
    if (this.model.expressionTypes.get(stmt.iterable) === STRING) b.emit(mkInst('string-symbols'))
    b.emit(mkStoreLocal(arraySlot))
    b.emit(mkPushInt('0'))
    b.emit(mkStoreLocal(indexSlot))
    let start = b.instructions.length
    b.emit(mkLoadLocal(indexSlot))
    b.emit(mkLoadLocal(arraySlot))
    b.emit(mkInst('length'))
    b.emit(mkBinary('<', true))
    let exit = b.emit(mkJumpIfFalse(-1))
    b.emit(mkLoadLocal(arraySlot))
    b.emit(mkLoadLocal(indexSlot))
    b.emit(mkInst('load-index'))
    b.emit(mkStoreLocal(varSlot))
    let loop = new LoopLabels([], [], -1)
    b.loops.push(loop)
    this.block(stmt.body, b)
    let advance = b.instructions.length
    b.emit(mkLoadLocal(indexSlot))
    b.emit(mkPushInt('1'))
    b.emit(mkBinary('+', true))
    b.emit(mkStoreLocal(indexSlot))
    b.emit(mkJump(start))
    let end = b.instructions.length
    this.patch(b, exit, end)
    let fixed = new LoopLabels(loop.breaks, loop.continues, advance)
    b.loops.pop()
    this.finishLoop(b, fixed, end, false)
  }

  private finishLoop(b: FunctionBuilder, loop: LoopLabels, end: number, pop: boolean): void {
    if (pop) b.loops.pop()
    for (let idx of loop.breaks) this.patch(b, idx, end)
    for (let idx of loop.continues) this.patch(b, idx, loop.continueTarget)
  }

  private assignment(stmt: AssignStatement, b: FunctionBuilder): void {
    let target = stmt.target
    if (target instanceof NameExpression) {
      this.expression(stmt.value, b)
      this.storeName(target.name, b)
    } else if (target instanceof IndexExpression) {
      this.expression(target.target, b)
      this.expression(target.index, b)
      this.expression(stmt.value, b)
      b.emit(mkInst('store-index'))
    } else if (target instanceof SelectExpression) {
      this.expression(target.target, b)
      this.expression(stmt.value, b)
      b.emit(mkStoreField(target.field))
    }
  }

  private expression(expr: Expression, b: FunctionBuilder): void {
    if (expr instanceof IntExpression) {
      // The analyzer recorded whether this literal sits in a number position.
      let recorded = this.model.expressionTypes.get(expr)
      if (recorded !== undefined && identical(recorded, NUMBER)) b.emit(mkPushNumber(expr.value))
      else b.emit(mkPushInt(expr.value.toString()))
    }
    else if (expr instanceof NumberExpression) b.emit(mkPushNumber(expr.value))
    else if (expr instanceof StringExpression) b.emit(mkPushString(expr.value))
    else if (expr instanceof BooleanExpression) b.emit(mkPushBoolean(expr.value))
    else if (expr instanceof NullExpression) b.emit(mkInst('push-null'))
    else if (expr instanceof NameExpression) this.loadName(expr.name, b)
    else if (expr instanceof UnaryExpression) {
      if (expr.operator === '-' && expr.operand instanceof IntExpression && expr.operand.value === 2147483648) {
        b.emit(mkPushInt('-2147483648'))
      } else {
        this.expression(expr.operand, b)
        b.emit(mkUnary(expr.operator))
      }
    }
    else if (expr instanceof BinaryExpression) this.binary(expr, b)
    else if (expr instanceof CallExpression) {
      if (expr.callee instanceof SelectExpression && expr.callee.field === 'push' && expr.argumentsList.length === 1 &&
        this.model.expressionTypes.get(expr.callee.target) instanceof VeraArrayType) {
        this.expression(expr.callee.target, b)
        this.expression(expr.argumentsList[0], b)
        b.emit(mkInst('array-push'))
      }
      else if (expr.callee instanceof SelectExpression && expr.callee.field === 'pop' && expr.argumentsList.length === 0 &&
        this.model.expressionTypes.get(expr.callee.target) instanceof VeraArrayType) {
        this.expression(expr.callee.target, b)
        b.emit(mkInst('array-pop'))
      }
      else if (expr.callee instanceof SelectExpression && expr.callee.field === 'length' && expr.argumentsList.length === 0) {
        this.expression(expr.callee.target, b)
        b.emit(mkInst('length'))
      } else {
        this.call(expr, b, false)
      }
    }
    else if (expr instanceof AwaitExpression) {
      if (expr.operand instanceof CallExpression) this.call(expr.operand, b, true)
    }
    else if (expr instanceof ArrayExpression) {
      for (let el of expr.elements) this.expression(el, b)
      b.emit(mkMakeArray(expr.elements.length))
    }
    else if (expr instanceof ObjectExpression) {
      for (let prop of expr.properties) this.expression(prop.value, b)
      let type = this.model.expressionTypes.get(expr)
      let identity = type instanceof VeraClassType ? type.identity : 'invalid'
      let fields: string[] = []
      for (let p of expr.properties) fields.push(p.name)
      b.emit(mkMakeObject(identity, fields))
    }
    else if (expr instanceof IndexExpression) {
      this.expression(expr.target, b)
      this.expression(expr.index, b)
      b.emit(mkInst('load-index'))
    }
    else if (expr instanceof EnsureNotNullExpression) {
      this.expression(expr.operand, b)
      b.emit(mkInst('ensure-not-null'))
    }
    else if (expr instanceof SelectExpression) {
      if (expr.target instanceof NameExpression) {
        let imported = this.model.imports.get(expr.target.name)
        if (imported !== undefined) {
          b.emit(mkLoadExternal(imported.specifier, expr.field))
          return
        }
      }
      this.expression(expr.target, b)
      b.emit(mkLoadField(expr.field))
    }
    else if (expr instanceof LambdaExpression) this.lambda(expr, b)
  }

  private binary(expr: BinaryExpression, b: FunctionBuilder): void {
    if (expr.operator === '&&') {
      this.expression(expr.left, b)
      let skip = b.emit(mkJumpIfFalse(-1))
      this.expression(expr.right, b)
      let end = b.emit(mkJump(-1))
      this.patch(b, skip, b.instructions.length)
      b.emit(mkPushBoolean(false))
      this.patch(b, end, b.instructions.length)
      return
    }
    if (expr.operator === '||') {
      this.expression(expr.left, b)
      b.emit(mkUnary('!'))
      let skip = b.emit(mkJumpIfFalse(-1))
      this.expression(expr.right, b)
      let end = b.emit(mkJump(-1))
      this.patch(b, skip, b.instructions.length)
      b.emit(mkPushBoolean(true))
      this.patch(b, end, b.instructions.length)
      return
    }
    this.expression(expr.left, b)
    this.expression(expr.right, b)
    let type = this.model.expressionTypes.get(expr.left)
    b.emit(mkBinary(expr.operator, type === INT))
  }

  private call(expr: CallExpression, b: FunctionBuilder, awaited: boolean): void {
    this.expression(expr.callee, b)
    for (let arg of expr.argumentsList) this.expression(arg, b)
    b.emit(mkCall(expr.argumentsList.length, awaited))
  }

  private lambda(expr: LambdaExpression, parent: FunctionBuilder): void {
    let name = '$lambda' + this.lambdaCount++
    let child = new FunctionBuilder(name, parent)
    for (let p of expr.parameters) child.local(p.name)
    this.block(expr.body, child)
    child.emit(mkInst('push-null'))
    child.emit(mkInst('return'))
    let captures: number[] = []
    let captureValues = Array.from(child.capturedBindings.values())
    for (let v of captureValues) captures.push(v)
    this.functions.push(new BytecodeFunction(name, expr.parameters.length, child.localCount, false, child.instructions))
    parent.emit(mkMakeClosure(name, captures))
  }

  private loadName(name: string, b: FunctionBuilder): void {
    let binding = b.bindings.get(name)
    if (binding !== undefined) {
      if (binding.location === 'local') b.emit(mkLoadLocal(binding.slot))
      else b.emit(mkLoadCapture(binding.slot))
      return
    }
    if (this.model.functions.has(name)) { b.emit(mkLoadFunction(name)); return }
    let pieces = name.split('.')
    if (pieces.length >= 2) {
      let imported = this.model.imports.get(pieces[0])
      if (imported !== undefined) {
        b.emit(mkLoadExternal(imported.specifier, pieces[1]))
        return
      }
    }
    let parent = b.parent
    if (parent !== null) {
      let parentBinding = this.findBinding(name, parent)
      if (parentBinding !== null) {
        let slot = b.capturedBindings.size
        let captureIdx = parentBinding.location === 'local' ? parentBinding.slot : -parentBinding.slot - 1
        b.capturedBindings.set(name, captureIdx)
        b.bindings.set(name, new Binding('capture', slot))
        b.emit(mkLoadCapture(slot))
        return
      }
    }
    b.emit(mkLoadFunction(name))
  }

  private storeName(name: string, b: FunctionBuilder): void {
    let binding = b.bindings.get(name)
    if (binding === undefined) throw new Error('compiler invariant')
    if (binding.location === 'local') b.emit(mkStoreLocal(binding.slot))
    else b.emit(mkStoreCapture(binding.slot))
  }

  private findBinding(name: string, b: FunctionBuilder): Binding | null {
    let found = b.bindings.get(name)
    if (found !== undefined) return found
    if (b.parent !== null) return this.findBinding(name, b.parent)
    return null
  }

  private patch(b: FunctionBuilder, index: number, target: number): void {
    let inst = b.instructions[index]
    if (inst.op === 'jump-if-false') {
      let newInst = mkJumpIfFalse(target)
      b.instructions[index] = newInst
    } else {
      let newInst = mkJump(target)
      b.instructions[index] = newInst
    }
  }
}

// ===== VBC2 Serialization =====

function encodeInstruction(inst: Instruction): Object[] {
  let op = inst.op
  switch (op) {
    case 'push-int': return [op, inst.value]
    case 'push-number': return [op, inst.numValue]
    case 'push-string': return [op, inst.value]
    case 'push-boolean': return [op, inst.boolValue]
    case 'push-null': return [op]
    case 'load-local': return [op, inst.slot]
    case 'store-local': return [op, inst.slot]
    case 'load-capture': return [op, inst.slot]
    case 'store-capture': return [op, inst.slot]
    case 'load-function': return [op, inst.name]
    case 'load-external': return [op, inst.module, inst.name]
    case 'pop': return [op]
    case 'duplicate': return [op]
    case 'unary': return [op, inst.operator]
    case 'binary': return [op, inst.operator, inst.integer]
    case 'jump': return [op, inst.target]
    case 'jump-if-false': return [op, inst.target]
    case 'call': return [op, inst.count, inst.awaited]
    case 'return': return [op]
    case 'make-array': return [op, inst.count]
    case 'array-push': return [op]
    case 'array-pop': return [op]
    case 'length': return [op]
    case 'string-symbols': return [op]
    case 'ensure-not-null': return [op]
    case 'load-index': return [op]
    case 'store-index': return [op]
    case 'make-object': return [op, inst.classIdentity, inst.fields]
    case 'load-field': return [op, inst.name]
    case 'store-field': return [op, inst.name]
    case 'make-closure': return [op, inst.functionName, inst.captures]
    default: return [op]
  }
}

function serializeVbc2(module: BytecodeModule): string {
  let functions: Object[] = []
  for (let fn of module.functions) {
    let instrs: Object[] = []
    for (let inst of fn.instructions) instrs.push(encodeInstruction(inst))
    functions.push([fn.name, fn.parameterCount, fn.localCount, fn.isAsync, instrs])
  }
  return JSON.stringify(['VBC2', module.entryCandidates, functions])
}

// ===== Public API =====

export class CompileResult {
  vbc2: string
  constructor(vbc2: string) { this.vbc2 = vbc2 }
}

export function compileVeraSource(source: string, sourceName: string = '<source>'): CompileResult {
  let app = new Parser(source, sourceName).parse()
  let model = new Analyzer(app).analyze()
  let module = new BytecodeCompiler(model).compile()
  return new CompileResult(serializeVbc2(module))
}
