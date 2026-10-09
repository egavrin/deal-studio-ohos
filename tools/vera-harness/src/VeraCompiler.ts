import { Instruction, BytecodeFunction, BytecodeModule } from "./VeraInterpreter";
import { CATALOG, stylesFor, payloadKindFor, childRuleFor, listWords } from "./VeraUiCatalog";
import type { ComponentSpec, ChildRule } from "./VeraUiCatalog";
import { iconPath, iconNames } from "./VeraIcons";
import { isValidSdkTarget } from "./VeraSdkIndex";
class Position {
    offset: number;
    line: number;
    column: number;
    constructor(f99: number, g99: number, h99: number) {
        this.offset = f99;
        this.line = g99;
        this.column = h99;
    }
}
class Span {
    start: Position;
    end: Position;
    sourceName: string;
    constructor(c99: Position, d99: Position, e99: string) {
        this.start = c99;
        this.end = d99;
        this.sourceName = e99;
    }
}
abstract class Node {
    span: Span;
    constructor(b99: Span) { this.span = b99; }
}
class TypeNode extends Node {
    name: string;
    parts: TypeNode[];
    nullable: boolean;
    constructor(x98: Span, y98: string, z98: TypeNode[] = [], a99: boolean = false) {
        super(x98);
        this.name = y98;
        this.parts = z98;
        this.nullable = a99;
    }
}
class Parameter extends Node {
    name: string;
    type: TypeNode;
    constructor(u98: Span, v98: string, w98: TypeNode) {
        super(u98);
        this.name = v98;
        this.type = w98;
    }
}
abstract class Declaration extends Node {
}
class ImportDeclaration extends Node {
    name: string;
    specifier: string;
    constructor(r98: Span, s98: string, t98: string) {
        super(r98);
        this.name = s98;
        this.specifier = t98;
    }
}
class FunctionDeclaration extends Declaration {
    name: string;
    parameters: Parameter[];
    returnType: TypeNode;
    body: BlockStatement;
    isAsync: boolean;
    constructor(l98: Span, m98: string, n98: Parameter[], o98: TypeNode, p98: BlockStatement, q98: boolean) {
        super(l98);
        this.name = m98;
        this.parameters = n98;
        this.returnType = o98;
        this.body = p98;
        this.isAsync = q98;
    }
}
class FieldDeclaration extends Node {
    name: string;
    type: TypeNode;
    constructor(i98: Span, j98: string, k98: TypeNode) {
        super(i98);
        this.name = j98;
        this.type = k98;
    }
}
class ClassDeclaration extends Declaration {
    name: string;
    fields: FieldDeclaration[];
    annotation: string | null;
    constructor(e98: Span, f98: string, g98: FieldDeclaration[], h98: string | null) {
        super(e98);
        this.name = f98;
        this.fields = g98;
        this.annotation = h98;
    }
}
class Application extends Node {
    imports: ImportDeclaration[];
    declarations: Declaration[];
    constructor(b98: Span, c98: ImportDeclaration[], d98: Declaration[]) {
        super(b98);
        this.imports = c98;
        this.declarations = d98;
    }
}
abstract class Statement extends Node {
}
class BlockStatement extends Statement {
    statements: Statement[];
    constructor(z97: Span, a98: Statement[]) {
        super(z97);
        this.statements = a98;
    }
}
class LetStatement extends Statement {
    name: string;
    type: TypeNode;
    initializer: Expression;
    constructor(v97: Span, w97: string, x97: TypeNode, y97: Expression) {
        super(v97);
        this.name = w97;
        this.type = x97;
        this.initializer = y97;
    }
}
class IfStatement extends Statement {
    condition: Expression;
    thenBranch: BlockStatement;
    elseBranch: Statement | null;
    constructor(r97: Span, s97: Expression, t97: BlockStatement, u97: Statement | null) {
        super(r97);
        this.condition = s97;
        this.thenBranch = t97;
        this.elseBranch = u97;
    }
}
class WhileStatement extends Statement {
    condition: Expression;
    body: BlockStatement;
    constructor(o97: Span, p97: Expression, q97: BlockStatement) {
        super(o97);
        this.condition = p97;
        this.body = q97;
    }
}
class ForOfStatement extends Statement {
    name: string;
    type: TypeNode;
    iterable: Expression;
    body: BlockStatement;
    constructor(j97: Span, k97: string, l97: TypeNode, m97: Expression, n97: BlockStatement) {
        super(j97);
        this.name = k97;
        this.type = l97;
        this.iterable = m97;
        this.body = n97;
    }
}
class BreakStatement extends Statement {
}
class ContinueStatement extends Statement {
}
class ReturnStatement extends Statement {
    value: Expression | null;
    constructor(h97: Span, i97: Expression | null) {
        super(h97);
        this.value = i97;
    }
}
class AssignStatement extends Statement {
    target: Expression;
    value: Expression;
    constructor(e97: Span, f97: Expression, g97: Expression) {
        super(e97);
        this.target = f97;
        this.value = g97;
    }
}
class ExpressionStatement extends Statement {
    expression: Expression;
    constructor(c97: Span, d97: Expression) {
        super(c97);
        this.expression = d97;
    }
}
class TryStatement extends Statement {
    tryBlock: BlockStatement;
    catchName: string;
    catchBlock: BlockStatement;
    constructor(y96: Span, z96: BlockStatement, a97: string, b97: BlockStatement) {
        super(y96);
        this.tryBlock = z96;
        this.catchName = a97;
        this.catchBlock = b97;
    }
}
abstract class Expression extends Node {
}
class NameExpression extends Expression {
    name: string;
    constructor(w96: Span, x96: string) { super(w96); this.name = x96; }
}
class IntExpression extends Expression {
    value: number;
    constructor(u96: Span, v96: number) { super(u96); this.value = v96; }
}
class NumberExpression extends Expression {
    value: number;
    constructor(s96: Span, t96: number) { super(s96); this.value = t96; }
}
class StringExpression extends Expression {
    value: string;
    constructor(q96: Span, r96: string) { super(q96); this.value = r96; }
}
class BooleanExpression extends Expression {
    value: boolean;
    constructor(o96: Span, p96: boolean) { super(o96); this.value = p96; }
}
class NullExpression extends Expression {
}
class UnaryExpression extends Expression {
    operator: string;
    operand: Expression;
    constructor(l96: Span, m96: string, n96: Expression) {
        super(l96);
        this.operator = m96;
        this.operand = n96;
    }
}
class BinaryExpression extends Expression {
    left: Expression;
    operator: string;
    right: Expression;
    constructor(h96: Span, i96: Expression, j96: string, k96: Expression) {
        super(h96);
        this.left = i96;
        this.operator = j96;
        this.right = k96;
    }
}
class CallExpression extends Expression {
    callee: Expression;
    argumentsList: Expression[];
    constructor(e96: Span, f96: Expression, g96: Expression[]) {
        super(e96);
        this.callee = f96;
        this.argumentsList = g96;
    }
}
class IndexExpression extends Expression {
    target: Expression;
    index: Expression;
    constructor(b96: Span, c96: Expression, d96: Expression) {
        super(b96);
        this.target = c96;
        this.index = d96;
    }
}
class SelectExpression extends Expression {
    target: Expression;
    field: string;
    constructor(y95: Span, z95: Expression, a96: string) {
        super(y95);
        this.target = z95;
        this.field = a96;
    }
}
class ArrayExpression extends Expression {
    elements: Expression[];
    constructor(w95: Span, x95: Expression[]) {
        super(w95);
        this.elements = x95;
    }
}
class Property extends Node {
    name: string;
    value: Expression;
    constructor(t95: Span, u95: string, v95: Expression) {
        super(t95);
        this.name = u95;
        this.value = v95;
    }
}
class ObjectExpression extends Expression {
    properties: Property[];
    constructor(r95: Span, s95: Property[]) {
        super(r95);
        this.properties = s95;
    }
}
class LambdaExpression extends Expression {
    parameters: Parameter[];
    returnType: TypeNode;
    body: BlockStatement;
    constructor(n95: Span, o95: Parameter[], p95: TypeNode, q95: BlockStatement) {
        super(n95);
        this.parameters = o95;
        this.returnType = p95;
        this.body = q95;
    }
}
class AwaitExpression extends Expression {
    operand: Expression;
    constructor(l95: Span, m95: Expression) { super(l95); this.operand = m95; }
}
class EnsureNotNullExpression extends Expression {
    operand: Expression;
    constructor(j95: Span, k95: Expression) { super(j95); this.operand = k95; }
}
abstract class VeraType {
    abstract display(): string;
}
class PrimitiveType extends VeraType {
    name: string;
    constructor(i95: string) { super(); this.name = i95; }
    display(): string { return this.name; }
}
class VeraClassType extends VeraType {
    identity: string;
    name: string;
    fields: Map<string, VeraType> = new Map<string, VeraType>();
    constructor(g95: string, h95: string) { super(); this.identity = g95; this.name = h95; }
    display(): string { return this.name; }
}
class VeraArrayType extends VeraType {
    element: VeraType;
    constructor(f95: VeraType) { super(); this.element = f95; }
    display(): string { return this.element.display() + '[]'; }
}
class NullableType extends VeraType {
    base: VeraType;
    constructor(e95: VeraType) { super(); this.base = e95; }
    display(): string { return '(' + this.base.display() + ' | null)'; }
}
class VeraFunctionType extends VeraType {
    parameters: VeraType[];
    result: VeraType;
    isAsync: boolean;
    identity: string;
    required: number;
    constructor(z94: VeraType[], a95: VeraType, b95: boolean, c95: string, d95: number = -1) {
        super();
        this.parameters = z94;
        this.result = a95;
        this.isAsync = b95;
        this.identity = c95;
        this.required = d95 < 0 ? z94.length : d95;
    }
    display(): string {
        let x94: string[] = [];
        for (let y94 = 0; y94 < this.parameters.length; y94++) {
            x94.push(this.parameters[y94].display());
        }
        return 'function (' + x94.join(', ') + '): ' + this.result.display();
    }
}
class NamespaceType extends VeraType {
    name: string;
    members: Map<string, VeraType>;
    constructor(v94: string, w94: Map<string, VeraType>) { super(); this.name = v94; this.members = w94; }
    display(): string { return 'namespace ' + this.name; }
}
class VeraNullType extends VeraType {
    display(): string { return 'null'; }
}
const INT = new PrimitiveType('int');
const NUMBER = new PrimitiveType('number');
const BOOLEAN = new PrimitiveType('boolean');
const STRING = new PrimitiveType('string');
const VOID = new PrimitiveType('void');
const NULL_TYPE = new VeraNullType();
function identical(s94: VeraType, t94: VeraType): boolean {
    if (s94 === t94)
        return true;
    if (s94 instanceof VeraArrayType && t94 instanceof VeraArrayType)
        return identical(s94.element, t94.element);
    if (s94 instanceof NullableType && t94 instanceof NullableType)
        return identical(s94.base, t94.base);
    if (s94 instanceof VeraFunctionType && t94 instanceof VeraFunctionType) {
        if (s94.isAsync !== t94.isAsync)
            return false;
        if (s94.parameters.length !== t94.parameters.length)
            return false;
        for (let u94 = 0; u94 < s94.parameters.length; u94++) {
            if (!identical(s94.parameters[u94], t94.parameters[u94]))
                return false;
        }
        return identical(s94.result, t94.result);
    }
    return false;
}
function subtypeOf(p94: VeraType, q94: VeraType): boolean {
    if (identical(p94, q94))
        return true;
    if (q94 instanceof NullableType && (subtypeOf(p94, q94.base) || p94 instanceof VeraNullType))
        return true;
    if (p94 instanceof VeraFunctionType && q94 instanceof VeraFunctionType) {
        if (p94.isAsync !== q94.isAsync)
            return false;
        if (p94.parameters.length > q94.parameters.length)
            return false;
        for (let r94 = 0; r94 < p94.parameters.length; r94++) {
            if (!subtypeOf(q94.parameters[r94], p94.parameters[r94]))
                return false;
        }
        return subtypeOf(p94.result, q94.result);
    }
    return false;
}
function assignable(n94: VeraType, o94: VeraType): boolean {
    return subtypeOf(n94, o94);
}
export class Diagnostic {
    code: string;
    message: string;
    span: Span;
    expected: string;
    actual: string;
    constructor(i94: string, j94: string, k94: Span, l94: string = '', m94: string = '') {
        this.code = i94;
        this.message = j94;
        this.span = k94;
        this.expected = l94;
        this.actual = m94;
    }
}
export class CompileError extends Error {
    diagnostics: Diagnostic[];
    constructor(f94: Diagnostic[]) {
        let g94: string[] = [];
        for (let h94 of f94) {
            g94.push(h94.span.start.line + ':' + h94.span.start.column + ' ' + h94.code + ' ' + h94.message);
        }
        super(g94.join('\n'));
        this.diagnostics = f94;
    }
}
class Token {
    kind: string;
    text: string;
    span: Span;
    constructor(c94: string, d94: string, e94: Span) {
        this.kind = c94;
        this.text = d94;
        this.span = e94;
    }
}
const KEYWORDS: string[] = [
    'import', 'as', 'from', 'class', 'function', 'async', 'let', 'if', 'else',
    'while', 'for', 'of', 'break', 'continue', 'return', 'true', 'false', 'null',
    'try', 'catch', 'new'
];
function isAlpha(b94: string): boolean {
    return (b94 >= 'a' && b94 <= 'z') || (b94 >= 'A' && b94 <= 'Z') || b94 === '_';
}
function isDigit(a94: string): boolean {
    return a94 >= '0' && a94 <= '9';
}
function isAlnum(z93: string): boolean {
    return isAlpha(z93) || isDigit(z93);
}
class Lexer {
    private source: string;
    private sourceName: string;
    private pos: number = 0;
    private line: number = 1;
    private col: number = 1;
    constructor(x93: string, y93: string) {
        this.source = x93;
        this.sourceName = y93;
    }
    scan(): Token[] {
        let u93: Token[] = [];
        while (this.pos < this.source.length) {
            this.skipWhitespaceAndComments();
            if (this.pos >= this.source.length)
                break;
            let v93 = this.makePos();
            let w93 = this.source[this.pos];
            if (isAlpha(w93)) {
                u93.push(this.scanIdentifier(v93));
                continue;
            }
            if (isDigit(w93)) {
                u93.push(this.scanNumber(v93));
                continue;
            }
            if (w93 === '"') {
                u93.push(this.scanString(v93));
                continue;
            }
            if (w93 === '@') {
                this.pos++;
                this.col++;
                u93.push(this.scanIdentifier(v93));
                u93[u93.length - 1].kind = 'annotation';
                continue;
            }
            u93.push(this.scanSymbol(v93));
        }
        u93.push(new Token('eof', '', this.makeSpan(this.makePos())));
        return u93;
    }
    private skipWhitespaceAndComments(): void {
        while (this.pos < this.source.length) {
            let t93 = this.source[this.pos];
            if (t93 === ' ' || t93 === '\t' || t93 === '\r') {
                this.pos++;
                this.col++;
                continue;
            }
            if (t93 === '\n') {
                this.pos++;
                this.line++;
                this.col = 1;
                continue;
            }
            if (t93 === '/' && this.pos + 1 < this.source.length && this.source[this.pos + 1] === '/') {
                while (this.pos < this.source.length && this.source[this.pos] !== '\n') {
                    this.pos++;
                    this.col++;
                }
                continue;
            }
            break;
        }
    }
    private scanIdentifier(o93: Position): Token {
        let p93 = this.pos;
        while (this.pos < this.source.length && isAlnum(this.source[this.pos])) {
            this.pos++;
            this.col++;
        }
        let q93 = this.source.substring(p93, this.pos);
        let r93 = 'name';
        if (q93 === 'true' || q93 === 'false')
            r93 = 'boolean';
        else if (q93 === 'null')
            r93 = 'null';
        else {
            for (let s93 of KEYWORDS) {
                if (s93 === q93) {
                    r93 = q93;
                    break;
                }
            }
        }
        return new Token(r93, q93, this.makeSpan(o93));
    }
    private scanNumber(m93: Position): Token {
        let n93 = this.pos;
        while (this.pos < this.source.length && isDigit(this.source[this.pos])) {
            this.pos++;
            this.col++;
        }
        if (this.pos < this.source.length && this.source[this.pos] === '.' && this.pos + 1 < this.source.length && isDigit(this.source[this.pos + 1])) {
            this.pos++;
            this.col++;
            while (this.pos < this.source.length && isDigit(this.source[this.pos])) {
                this.pos++;
                this.col++;
            }
            return new Token('number', this.source.substring(n93, this.pos), this.makeSpan(m93));
        }
        return new Token('integer', this.source.substring(n93, this.pos), this.makeSpan(m93));
    }
    private scanString(j93: Position): Token {
        this.pos++;
        this.col++;
        let k93 = '';
        while (this.pos < this.source.length && this.source[this.pos] !== '"') {
            if (this.source[this.pos] === '\\') {
                this.pos++;
                this.col++;
                if (this.pos >= this.source.length)
                    break;
                let l93 = this.source[this.pos];
                if (l93 === 'n')
                    k93 += '\n';
                else if (l93 === 't')
                    k93 += '\t';
                else if (l93 === '\\')
                    k93 += '\\';
                else if (l93 === '"')
                    k93 += '"';
                else
                    k93 += l93;
                this.pos++;
                this.col++;
            }
            else {
                if (this.source[this.pos] === '\n') {
                    this.line++;
                    this.col = 0;
                }
                k93 += this.source[this.pos];
                this.pos++;
                this.col++;
            }
        }
        if (this.pos < this.source.length) {
            this.pos++;
            this.col++;
        }
        return new Token('string', k93, this.makeSpan(j93));
    }
    private scanSymbol(g93: Position): Token {
        let h93 = this.source[this.pos];
        this.pos++;
        this.col++;
        if (this.pos < this.source.length) {
            let i93 = h93 + this.source[this.pos];
            if (i93 === '==') {
                this.pos++;
                this.col++;
                if (this.pos < this.source.length && this.source[this.pos] === '=') {
                    this.pos++;
                    this.col++;
                    return new Token('===', '===', this.makeSpan(g93));
                }
                return new Token('==', '==', this.makeSpan(g93));
            }
            if (i93 === '!=') {
                this.pos++;
                this.col++;
                if (this.pos < this.source.length && this.source[this.pos] === '=') {
                    this.pos++;
                    this.col++;
                    return new Token('!==', '!==', this.makeSpan(g93));
                }
                return new Token('!=', '!=', this.makeSpan(g93));
            }
            if (i93 === '&&' || i93 === '||' || i93 === '<=' || i93 === '>=') {
                this.pos++;
                this.col++;
                return new Token(i93, i93, this.makeSpan(g93));
            }
        }
        return new Token(h93, h93, this.makeSpan(g93));
    }
    private makePos(): Position { return new Position(this.pos, this.line, this.col); }
    private makeSpan(f93: Position): Span { return new Span(f93, this.makePos(), this.sourceName); }
}
class Parser {
    private tokens: Token[];
    private pos: number = 0;
    private sourceName: string;
    constructor(d93: string, e93: string) {
        this.sourceName = e93;
        this.tokens = new Lexer(d93, e93).scan();
    }
    parse(): Application {
        let z92 = this.current().span;
        let a93: ImportDeclaration[] = [];
        let b93: Declaration[] = [];
        while (!this.atEnd()) {
            if (this.check('import')) {
                a93.push(this.parseImport());
                continue;
            }
            if (this.check('annotation')) {
                let c93 = this.advance();
                b93.push(this.parseClass(c93.text));
                continue;
            }
            if (this.check('class')) {
                b93.push(this.parseClass(null));
                continue;
            }
            if (this.check('async')) {
                b93.push(this.parseFunction());
                continue;
            }
            if (this.check('function')) {
                b93.push(this.parseFunction());
                continue;
            }
            this.error('expected import, class, or function declaration');
        }
        return new Application(this.span(z92), a93, b93);
    }
    private parseImport(): ImportDeclaration {
        let w92 = this.current().span;
        this.expect('import');
        this.expect('*');
        this.expect('as');
        let x92 = this.expect('name').text;
        this.expect('from');
        let y92 = this.expect('string').text;
        return new ImportDeclaration(this.span(w92), x92, y92);
    }
    private parseClass(p92: string | null): ClassDeclaration {
        let q92 = this.current().span;
        this.expect('class');
        let r92 = this.expect('name').text;
        this.expect('{');
        let s92: FieldDeclaration[] = [];
        while (!this.check('}') && !this.atEnd()) {
            let t92 = this.current().span;
            let u92 = this.expect('name').text;
            this.expect(':');
            let v92 = this.parseType();
            if (this.check(';'))
                this.advance();
            s92.push(new FieldDeclaration(this.span(t92), u92, v92));
        }
        this.expect('}');
        return new ClassDeclaration(this.span(q92), r92, s92, p92);
    }
    private parseFunction(): FunctionDeclaration {
        let j92 = this.current().span;
        let k92 = false;
        if (this.check('async')) {
            this.advance();
            k92 = true;
        }
        this.expect('function');
        let l92 = this.expect('name').text;
        this.expect('(');
        let m92 = this.parseParameters();
        this.expect(')');
        this.expect(':');
        let n92 = this.parseType();
        let o92 = this.parseBlock();
        return new FunctionDeclaration(this.span(j92), l92, m92, n92, o92, k92);
    }
    private parseParameters(): Parameter[] {
        let f92: Parameter[] = [];
        if (this.check(')'))
            return f92;
        while (true) {
            let g92 = this.current().span;
            let h92 = this.expect('name').text;
            this.expect(':');
            let i92 = this.parseType();
            f92.push(new Parameter(this.span(g92), h92, i92));
            if (!this.check(','))
                break;
            this.advance();
        }
        return f92;
    }
    private parseType(): TypeNode {
        let d92 = this.current().span;
        let e92 = this.parseBaseType();
        if (this.check('|')) {
            this.advance();
            this.expect('null');
            e92 = new TypeNode(this.span(d92), e92.name, e92.parts, true);
        }
        return e92;
    }
    private parseBaseType(): TypeNode {
        let t91 = this.current().span;
        if (this.check('(')) {
            this.advance();
            let a92: TypeNode[] = [];
            if (!this.check(')')) {
                while (true) {
                    let c92 = this.current().span;
                    this.expect('name');
                    this.expect(':');
                    a92.push(this.parseType());
                    if (!this.check(','))
                        break;
                    this.advance();
                }
            }
            this.expect(')');
            this.expect('=');
            this.expect('>');
            let b92 = this.parseType();
            a92.push(b92);
            return new TypeNode(this.span(t91), 'function', a92);
        }
        if (this.check('async')) {
            this.advance();
            this.expect('(');
            let x91: TypeNode[] = [];
            if (!this.check(')')) {
                while (true) {
                    let z91 = this.current().span;
                    this.expect('name');
                    this.expect(':');
                    x91.push(this.parseType());
                    if (!this.check(','))
                        break;
                    this.advance();
                }
            }
            this.expect(')');
            this.expect('=');
            this.expect('>');
            let y91 = this.parseType();
            x91.push(y91);
            return new TypeNode(this.span(t91), 'async-function', x91);
        }
        let u91 = this.expect('name').text;
        if (this.check('.')) {
            this.advance();
            let w91 = this.expect('name').text;
            u91 = u91 + '.' + w91;
        }
        if (this.check('[')) {
            this.advance();
            this.expect(']');
            let v91 = new TypeNode(this.span(t91), u91);
            return new TypeNode(this.span(t91), 'array', [v91]);
        }
        return new TypeNode(this.span(t91), u91);
    }
    private parseBlock(): BlockStatement {
        let r91 = this.current().span;
        this.expect('{');
        let s91: Statement[] = [];
        while (!this.check('}') && !this.atEnd()) {
            s91.push(this.parseStatement());
        }
        this.expect('}');
        return new BlockStatement(this.span(r91), s91);
    }
    private parseStatement(): Statement {
        if (this.check('let'))
            return this.parseLet();
        if (this.check('if'))
            return this.parseIf();
        if (this.check('while'))
            return this.parseWhile();
        if (this.check('for'))
            return this.parseFor();
        if (this.check('break')) {
            let q91 = this.current().span;
            this.advance();
            if (this.check(';'))
                this.advance();
            return new BreakStatement(this.span(q91));
        }
        if (this.check('continue')) {
            let p91 = this.current().span;
            this.advance();
            if (this.check(';'))
                this.advance();
            return new ContinueStatement(this.span(p91));
        }
        if (this.check('return'))
            return this.parseReturn();
        if (this.check('try'))
            return this.parseTry();
        if (this.check('{'))
            return this.parseBlock();
        return this.parseExpressionOrAssign();
    }
    private parseLet(): LetStatement {
        let l91 = this.current().span;
        this.expect('let');
        let m91 = this.expect('name').text;
        this.expect(':');
        let n91 = this.parseType();
        this.expect('=');
        let o91 = this.parseExpression();
        if (this.check(';'))
            this.advance();
        return new LetStatement(this.span(l91), m91, n91, o91);
    }
    private parseIf(): IfStatement {
        let h91 = this.current().span;
        this.expect('if');
        this.expect('(');
        let i91 = this.parseExpression();
        this.expect(')');
        let j91 = this.parseBlock();
        let k91: Statement | null = null;
        if (this.check('else')) {
            this.advance();
            if (this.check('if'))
                k91 = this.parseIf();
            else
                k91 = this.parseBlock();
        }
        return new IfStatement(this.span(h91), i91, j91, k91);
    }
    private parseWhile(): WhileStatement {
        let e91 = this.current().span;
        this.expect('while');
        this.expect('(');
        let f91 = this.parseExpression();
        this.expect(')');
        let g91 = this.parseBlock();
        return new WhileStatement(this.span(e91), f91, g91);
    }
    private parseFor(): ForOfStatement {
        let z90 = this.current().span;
        this.expect('for');
        this.expect('(');
        this.expect('let');
        let a91 = this.expect('name').text;
        this.expect(':');
        let b91 = this.parseType();
        this.expect('of');
        let c91 = this.parseExpression();
        this.expect(')');
        let d91 = this.parseBlock();
        return new ForOfStatement(this.span(z90), a91, b91, c91, d91);
    }
    private parseReturn(): ReturnStatement {
        let x90 = this.current().span;
        this.expect('return');
        let y90: Expression | null = null;
        if (!this.check('}') && !this.check(';') && !this.atEnd()) {
            y90 = this.parseExpression();
        }
        if (this.check(';'))
            this.advance();
        return new ReturnStatement(this.span(x90), y90);
    }
    private parseTry(): TryStatement {
        let t90 = this.current().span;
        this.expect('try');
        let u90 = this.parseBlock();
        this.expect('catch');
        this.expect('(');
        let v90 = this.expect('name').text;
        this.expect(')');
        let w90 = this.parseBlock();
        return new TryStatement(this.span(t90), u90, v90, w90);
    }
    private parseExpressionOrAssign(): Statement {
        let q90 = this.current().span;
        let r90 = this.parseExpression();
        if (this.check('=')) {
            this.advance();
            let s90 = this.parseExpression();
            if (this.check(';'))
                this.advance();
            return new AssignStatement(this.span(q90), r90, s90);
        }
        if (this.check(';'))
            this.advance();
        return new ExpressionStatement(this.span(q90), r90);
    }
    private parseExpression(): Expression {
        return this.parseBinary(0);
    }
    private parseBinary(k90: number): Expression {
        let l90 = this.parseUnary();
        while (true) {
            let m90 = this.current().kind;
            let n90 = this.precedence(m90);
            if (n90 < 0 || n90 < k90)
                break;
            let o90 = l90.span;
            this.advance();
            let p90 = this.parseBinary(n90 + 1);
            l90 = new BinaryExpression(this.span(o90), l90, m90, p90);
        }
        return l90;
    }
    private precedence(j90: string): number {
        if (j90 === '||')
            return 1;
        if (j90 === '&&')
            return 2;
        if (j90 === '===' || j90 === '!==')
            return 3;
        if (j90 === '<' || j90 === '<=' || j90 === '>' || j90 === '>=')
            return 4;
        if (j90 === '+' || j90 === '-')
            return 5;
        if (j90 === '*' || j90 === '/' || j90 === '%')
            return 6;
        return -1;
    }
    private parseUnary(): Expression {
        let f90 = this.current().span;
        if (this.check('-')) {
            this.advance();
            let i90 = this.parseUnary();
            return new UnaryExpression(this.span(f90), '-', i90);
        }
        if (this.check('!')) {
            this.advance();
            let h90 = this.parseUnary();
            return new UnaryExpression(this.span(f90), '!', h90);
        }
        if (this.check('await')) {
            this.advance();
            let g90 = this.parseUnary();
            return new AwaitExpression(this.span(f90), g90);
        }
        return this.parsePostfix();
    }
    private parsePostfix(): Expression {
        let x89 = this.parsePrimary();
        while (true) {
            if (this.check('(')) {
                let d90 = x89.span;
                this.advance();
                let e90: Expression[] = [];
                if (!this.check(')')) {
                    while (true) {
                        e90.push(this.parseExpression());
                        if (!this.check(','))
                            break;
                        this.advance();
                    }
                }
                this.expect(')');
                x89 = new CallExpression(this.span(d90), x89, e90);
            }
            else if (this.check('[')) {
                let b90 = x89.span;
                this.advance();
                let c90 = this.parseExpression();
                this.expect(']');
                x89 = new IndexExpression(this.span(b90), x89, c90);
            }
            else if (this.check('.')) {
                let z89 = x89.span;
                this.advance();
                let a90 = this.expect('name').text;
                x89 = new SelectExpression(this.span(z89), x89, a90);
            }
            else if (this.check('!')) {
                let y89 = x89.span;
                this.advance();
                x89 = new EnsureNotNullExpression(this.span(y89), x89);
            }
            else {
                break;
            }
        }
        return x89;
    }
    private parsePrimary(): Expression {
        let j89 = this.current().span;
        if (this.check('name')) {
            let w89 = this.advance().text;
            return new NameExpression(this.span(j89), w89);
        }
        if (this.check('integer')) {
            let u89 = this.advance().text;
            let v89 = parseInt(u89);
            return new IntExpression(this.span(j89), v89);
        }
        if (this.check('number')) {
            let s89 = this.advance().text;
            let t89 = parseFloat(s89);
            return new NumberExpression(this.span(j89), t89);
        }
        if (this.check('string')) {
            let r89 = this.advance().text;
            return new StringExpression(this.span(j89), r89);
        }
        if (this.check('boolean')) {
            let q89 = this.advance().text;
            return new BooleanExpression(this.span(j89), q89 === 'true');
        }
        if (this.check('null')) {
            this.advance();
            return new NullExpression(this.span(j89));
        }
        if (this.check('(')) {
            this.advance();
            if (this.check(')') || this.isLambdaStart()) {
                return this.parseLambda(j89);
            }
            let p89 = this.parseExpression();
            this.expect(')');
            return p89;
        }
        if (this.check('[')) {
            this.advance();
            let o89: Expression[] = [];
            if (!this.check(']')) {
                while (true) {
                    o89.push(this.parseExpression());
                    if (!this.check(','))
                        break;
                    this.advance();
                }
            }
            this.expect(']');
            return new ArrayExpression(this.span(j89), o89);
        }
        if (this.check('{')) {
            this.advance();
            let k89: Property[] = [];
            if (!this.check('}')) {
                while (true) {
                    let l89 = this.current().span;
                    let m89 = this.expect('name').text;
                    this.expect(':');
                    let n89 = this.parseExpression();
                    k89.push(new Property(this.span(l89), m89, n89));
                    if (!this.check(','))
                        break;
                    this.advance();
                }
            }
            this.expect('}');
            return new ObjectExpression(this.span(j89), k89);
        }
        this.error('expected expression');
        return new NullExpression(this.span(j89));
    }
    private isLambdaStart(): boolean {
        let h89 = this.pos;
        if (this.check('name')) {
            this.advance();
            let i89 = this.check(':');
            this.pos = h89;
            return i89;
        }
        this.pos = h89;
        return false;
    }
    private parseLambda(a89: Span): LambdaExpression {
        let b89: Parameter[] = [];
        if (!this.check(')')) {
            while (true) {
                let e89 = this.current().span;
                let f89 = this.expect('name').text;
                this.expect(':');
                let g89 = this.parseType();
                b89.push(new Parameter(this.span(e89), f89, g89));
                if (!this.check(','))
                    break;
                this.advance();
            }
        }
        this.expect(')');
        this.expect(':');
        let c89 = this.parseType();
        this.expect('=');
        this.expect('>');
        let d89 = this.parseBlock();
        return new LambdaExpression(this.span(a89), b89, c89, d89);
    }
    private current(): Token { return this.tokens[this.pos]; }
    private atEnd(): boolean { return this.current().kind === 'eof'; }
    private check(z88: string): boolean { return this.current().kind === z88; }
    private advance(): Token { let y88 = this.current(); this.pos++; return y88; }
    private expect(x88: string): Token {
        if (!this.check(x88))
            this.error('expected ' + x88 + ', found ' + this.current().kind);
        return this.advance();
    }
    private span(w88: Span): Span { return new Span(w88.start, this.tokens[this.pos > 0 ? this.pos - 1 : 0].span.end, this.sourceName); }
    private error(u88: string): never {
        let v88 = this.current().span;
        throw new CompileError([new Diagnostic('E1001', u88, v88)]);
    }
}
class ExternalFunction {
    name: string;
    parameters: VeraType[];
    result: VeraType;
    isAsync: boolean;
    required: number;
    constructor(p88: string, q88: VeraType[], r88: VeraType, s88: boolean, t88: number = -1) {
        this.name = p88;
        this.parameters = q88;
        this.result = r88;
        this.isAsync = s88;
        this.required = t88 < 0 ? q88.length : t88;
    }
}
class ExternalClass {
    name: string;
    type: VeraClassType;
    constructor(n88: string, o88: VeraClassType) {
        this.name = n88;
        this.type = o88;
    }
}
class ModuleInterface {
    specifier: string;
    functions: ExternalFunction[];
    classes: ExternalClass[];
    constructor(k88: string, l88: ExternalFunction[], m88: ExternalClass[]) {
        this.specifier = k88;
        this.functions = l88;
        this.classes = m88;
    }
}
function buildStdUiModule(): ModuleInterface {
    let d88 = new VeraClassType('std/ui:View', 'View');
    let e88 = new VeraArrayType(d88);
    let f88: ExternalFunction[] = [];
    for (let g88 of CATALOG) {
        let h88: VeraType[] = [];
        for (let j88 of g88.props) {
            if (j88.kind === 'int')
                h88.push(INT);
            else if (j88.kind === 'boolean')
                h88.push(BOOLEAN);
            else if (j88.kind === 'view')
                h88.push(d88);
            else if (j88.kind === 'view[]')
                h88.push(e88);
            else if (j88.kind === 'string[]')
                h88.push(new VeraArrayType(STRING));
            else if (j88.kind === 'int[]')
                h88.push(new VeraArrayType(INT));
            else
                h88.push(STRING);
        }
        let i88 = h88.length;
        while (i88 > 0 && g88.props[i88 - 1].optional) {
            i88 -= 1;
        }
        f88.push(new ExternalFunction(g88.name, h88, d88, false, i88));
    }
    f88.push(new ExternalFunction('When', [BOOLEAN, d88], d88, false));
    f88.push(new ExternalFunction('intToString', [INT], STRING, false));
    f88.push(new ExternalFunction('numberToString', [NUMBER], STRING, false));
    f88.push(new ExternalFunction('booleanToString', [BOOLEAN], STRING, false));
    return new ModuleInterface('std/ui', f88, [new ExternalClass('View', d88)]);
}
function buildStdMathModule(): ModuleInterface {
    let c88: ExternalFunction[] = [
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
        new ExternalFunction('randomStep', [INT], INT, false),
        new ExternalFunction('randomBelow', [INT, INT], INT, false),
    ];
    return new ModuleInterface('std/math', c88, []);
}
function buildStdTimeModule(): ModuleInterface {
    let b88: ExternalFunction[] = [
        new ExternalFunction('nowSeconds', [], INT, false),
        new ExternalFunction('millisOfDay', [], INT, false),
        new ExternalFunction('daysSinceEpoch', [], INT, false),
        new ExternalFunction('hourOfDay', [], INT, false),
        new ExternalFunction('minuteOfHour', [], INT, false),
        new ExternalFunction('weekday', [], INT, false),
        new ExternalFunction('dayOfMonth', [], INT, false),
        new ExternalFunction('monthOfYear', [], INT, false),
        new ExternalFunction('year', [], INT, false),
    ];
    return new ModuleInterface('std/time', b88, []);
}
function buildStdStringsModule(): ModuleInterface {
    let a88: ExternalFunction[] = [
        new ExternalFunction('length', [STRING], INT, false),
        new ExternalFunction('substring', [STRING, INT, INT], STRING, false),
        new ExternalFunction('contains', [STRING, STRING], BOOLEAN, false),
        new ExternalFunction('startsWith', [STRING, STRING], BOOLEAN, false),
        new ExternalFunction('endsWith', [STRING, STRING], BOOLEAN, false),
        new ExternalFunction('replace', [STRING, STRING, STRING], STRING, false),
        new ExternalFunction('split', [STRING, STRING], new VeraArrayType(STRING), false),
        new ExternalFunction('trim', [STRING], STRING, false),
    ];
    return new ModuleInterface('std/strings', a88, []);
}
function buildStdSdkModule(): ModuleInterface {
    let z87: ExternalFunction[] = [
        new ExternalFunction('call', [STRING, new VeraArrayType(STRING), STRING, STRING], INT, false, 3)
    ];
    return new ModuleInterface('std/sdk', z87, []);
}
class Scope {
    values: Map<string, VeraType> = new Map<string, VeraType>();
    parent: Scope | null;
    constructor(y87: Scope | null) { this.parent = y87; }
    find(w87: string): VeraType | null {
        let x87 = this.values.get(w87);
        if (x87 !== undefined)
            return x87;
        if (this.parent !== null)
            return this.parent.find(w87);
        return null;
    }
}
class SemanticModel {
    expressionTypes: Map<Expression, VeraType> = new Map<Expression, VeraType>();
    declaredTypes: Map<TypeNode, VeraType> = new Map<TypeNode, VeraType>();
    functions: Map<string, VeraFunctionType> = new Map<string, VeraFunctionType>();
    classes: Map<string, VeraClassType> = new Map<string, VeraClassType>();
    imports: Map<string, ModuleInterface> = new Map<string, ModuleInterface>();
    application: Application;
    constructor(v87: Application) { this.application = v87; }
}
class Narrowing {
    whenTrue: Scope;
    whenFalse: Scope;
    constructor(t87: Scope, u87: Scope) { this.whenTrue = t87; this.whenFalse = u87; }
}
class Analyzer {
    private diagnostics: Diagnostic[] = [];
    private model: SemanticModel;
    private globals: Scope = new Scope(null);
    private returnType: VeraType = VOID;
    private inAsyncFunction: boolean = false;
    private loopDepth: number = 0;
    private lambdaCount: number = 0;
    constructor(s87: Application) {
        this.model = new SemanticModel(s87);
    }
    analyze(): SemanticModel {
        this.collectImports();
        for (let q87 of this.model.application.declarations) {
            if (!(q87 instanceof ClassDeclaration) && !(q87 instanceof FunctionDeclaration))
                continue;
            if (this.globals.find(q87.name) !== null) {
                this.addError('E2001', 'duplicate global ' + q87.name, q87.span);
                continue;
            }
            if (q87 instanceof ClassDeclaration) {
                let r87 = new VeraClassType('local:' + q87.name, q87.name);
                this.model.classes.set(q87.name, r87);
                this.globals.values.set(q87.name, r87);
            }
            else {
                this.globals.values.set(q87.name, new VeraFunctionType([], VOID, (q87 as FunctionDeclaration).isAsync, 'pending:' + q87.name));
            }
        }
        for (let l87 of this.model.application.declarations) {
            if (!(l87 instanceof FunctionDeclaration))
                continue;
            let m87: VeraType[] = [];
            for (let p87 of l87.parameters)
                m87.push(this.resolveType(p87.type));
            let n87 = this.resolveType(l87.returnType);
            let o87 = new VeraFunctionType(m87, n87, l87.isAsync, 'function:' + l87.name);
            this.model.functions.set(l87.name, o87);
            this.globals.values.set(l87.name, o87);
        }
        for (let k87 of this.model.application.declarations) {
            if (k87 instanceof ClassDeclaration)
                this.checkClass(k87);
        }
        this.checkJsonableCycles();
        for (let j87 of this.model.application.declarations) {
            if (j87 instanceof FunctionDeclaration)
                this.checkFunction(j87);
        }
        if (this.diagnostics.length > 0)
            throw new CompileError(this.diagnostics);
        return this.model;
    }
    private collectImports(): void {
        let c87 = new Map<string, ModuleInterface>();
        c87.set('std/ui', buildStdUiModule());
        c87.set('std/time', buildStdTimeModule());
        c87.set('std/math', buildStdMathModule());
        c87.set('std/strings', buildStdStringsModule());
        c87.set('std/sdk', buildStdSdkModule());
        for (let d87 of this.model.application.imports) {
            if (this.globals.find(d87.name) !== null) {
                this.addError('E2001', 'duplicate global ' + d87.name, d87.span);
                continue;
            }
            let e87 = c87.get(d87.specifier);
            let f87: ModuleInterface | null = e87 !== undefined ? e87 : null;
            if (f87 === null) {
                this.addError('E2002', 'module not found: ' + d87.specifier, d87.span);
                continue;
            }
            let g87 = new Map<string, VeraType>();
            for (let i87 of f87.functions)
                g87.set(i87.name, new VeraFunctionType(i87.parameters, i87.result, i87.isAsync, 'external:' + f87.specifier + ':' + i87.name, i87.required));
            for (let h87 of f87.classes)
                g87.set(h87.name, h87.type);
            this.model.imports.set(d87.name, f87);
            this.globals.values.set(d87.name, new NamespaceType(d87.name, g87));
        }
    }
    private checkClass(z86: ClassDeclaration): void {
        let a87 = this.model.classes.get(z86.name);
        if (a87 === undefined)
            return;
        if (z86.annotation !== null && z86.annotation !== 'jsonable')
            this.addError('E2039', 'unknown annotation ' + z86.annotation, z86.span);
        for (let b87 of z86.fields) {
            if (a87.fields.has(b87.name))
                this.addError('E2003', 'duplicate field ' + b87.name, b87.span);
            else
                a87.fields.set(b87.name, this.resolveType(b87.type));
        }
    }
    private checkJsonableCycles(): void {
        let s86: ClassDeclaration[] = [];
        for (let y86 of this.model.application.declarations) {
            if (y86 instanceof ClassDeclaration && y86.annotation === 'jsonable')
                s86.push(y86);
        }
        let t86 = new Set<string>();
        let u86 = new Set<string>();
        let v86 = new Set<string>();
        for (let x86 of s86)
            v86.add(x86.name);
        for (let w86 of s86) {
            if (this.visitJsonable(w86.name, v86, t86, u86)) {
                this.addError('E2040', 'circular jsonable dependency involving ' + w86.name, w86.span);
                break;
            }
        }
    }
    private visitJsonable(k86: string, l86: Set<string>, m86: Set<string>, n86: Set<string>): boolean {
        if (m86.has(k86))
            return true;
        if (n86.has(k86))
            return false;
        m86.add(k86);
        let o86 = this.model.classes.get(k86);
        if (o86 !== undefined) {
            let p86 = Array.from(o86.fields.values());
            for (let q86 of p86) {
                let r86 = this.localClass(q86);
                if (r86 !== null && l86.has(r86.name) && this.visitJsonable(r86.name, l86, m86, n86))
                    return true;
            }
        }
        m86.delete(k86);
        n86.add(k86);
        return false;
    }
    private localClass(j86: VeraType): VeraClassType | null {
        if (j86 instanceof NullableType)
            return this.localClass(j86.base);
        if (j86 instanceof VeraArrayType)
            return this.localClass(j86.element);
        if (j86 instanceof VeraClassType && j86.identity.startsWith('local:'))
            return j86;
        return null;
    }
    private checkFunction(b86: FunctionDeclaration): void {
        let c86 = this.model.functions.get(b86.name);
        if (c86 === undefined)
            return;
        let d86 = this.returnType;
        let e86 = this.inAsyncFunction;
        this.returnType = c86.result;
        this.inAsyncFunction = b86.isAsync;
        let f86 = new Scope(this.globals);
        for (let h86 = 0; h86 < b86.parameters.length; h86++) {
            let i86 = b86.parameters[h86];
            if (f86.find(i86.name) !== null)
                this.addError('E2004', 'declaration ' + i86.name + ' shadows a visible entity', i86.span);
            else
                f86.values.set(i86.name, c86.parameters[h86]);
        }
        let g86 = this.checkBlock(b86.body, f86);
        if (!identical(this.returnType, VOID) && !g86)
            this.addError('E2018', 'function ' + b86.name + ' may not return a value', b86.body.span);
        this.returnType = d86;
        this.inAsyncFunction = e86;
    }
    private checkBlock(w85: BlockStatement, x85: Scope): boolean {
        let y85 = new Scope(x85);
        let z85 = false;
        for (let a86 of w85.statements) {
            if (this.checkStatement(a86, y85))
                z85 = true;
        }
        return z85;
    }
    private checkStatement(i85: Statement, j85: Scope): boolean {
        if (i85 instanceof BlockStatement)
            return this.checkBlock(i85, j85);
        if (i85 instanceof LetStatement) {
            let v85 = this.resolveType(i85.type);
            this.checkExpression(i85.initializer, j85, v85);
            if (j85.find(i85.name) !== null)
                this.addError('E2004', 'declaration ' + i85.name + ' shadows a visible entity', i85.span);
            else
                j85.values.set(i85.name, v85);
            return false;
        }
        if (i85 instanceof AssignStatement) {
            let u85 = this.checkAssignable(i85.target, j85);
            this.checkExpression(i85.value, j85, u85);
            return false;
        }
        if (i85 instanceof ExpressionStatement) {
            this.checkExpression(i85.expression, j85, null);
            if (!(i85.expression instanceof CallExpression) && !(i85.expression instanceof AwaitExpression)) {
                this.addError('E2005', 'expression statement must be a function call', i85.span);
            }
            return false;
        }
        if (i85 instanceof IfStatement) {
            this.requireType(this.checkExpression(i85.condition, j85, BOOLEAN), BOOLEAN, i85.condition);
            let r85 = this.narrow(i85.condition, j85);
            let s85 = this.checkBlock(i85.thenBranch, r85.whenTrue);
            let t85 = i85.elseBranch === null ? false : this.checkStatement(i85.elseBranch, r85.whenFalse);
            return s85 && t85;
        }
        if (i85 instanceof WhileStatement) {
            this.requireType(this.checkExpression(i85.condition, j85, BOOLEAN), BOOLEAN, i85.condition);
            this.loopDepth += 1;
            this.checkBlock(i85.body, j85);
            this.loopDepth -= 1;
            return false;
        }
        if (i85 instanceof ForOfStatement) {
            let n85 = this.checkExpression(i85.iterable, j85, null);
            let o85 = this.resolveType(i85.type);
            let p85: VeraType | null = null;
            if (n85 instanceof VeraArrayType)
                p85 = n85.element;
            else if (identical(n85, STRING))
                p85 = STRING;
            else
                this.addError('E2006', 'for-of requires an array or string', i85.iterable.span);
            if (p85 !== null && !identical(p85, o85))
                this.typeError(i85.iterable, o85, p85);
            let q85 = new Scope(j85);
            if (q85.find(i85.name) !== null)
                this.addError('E2004', 'declaration ' + i85.name + ' shadows a visible entity', i85.span);
            else
                q85.values.set(i85.name, o85);
            this.loopDepth += 1;
            this.checkBlock(i85.body, q85);
            this.loopDepth -= 1;
            return false;
        }
        if (i85 instanceof BreakStatement || i85 instanceof ContinueStatement) {
            if (this.loopDepth === 0)
                this.addError('E2007', 'loop control used outside a loop', i85.span);
            return false;
        }
        if (i85 instanceof TryStatement) {
            let k85 = this.checkBlock(i85.tryBlock, j85);
            let l85 = new Scope(j85);
            l85.values.set(i85.catchName, STRING);
            let m85 = this.checkBlock(i85.catchBlock, l85);
            return k85 && m85;
        }
        if (i85 instanceof ReturnStatement) {
            if (i85.value === null) {
                if (!identical(this.returnType, VOID))
                    this.addError('E2008', 'return value required', i85.span);
            }
            else {
                if (identical(this.returnType, VOID))
                    this.addError('E2009', 'void function cannot return a value', i85.span);
                else
                    this.checkExpression(i85.value, j85, this.returnType);
            }
            return true;
        }
        return false;
    }
    private checkAssignable(f85: Expression, g85: Scope): VeraType {
        if (f85 instanceof NameExpression) {
            let h85 = g85.find(f85.name);
            if (h85 === null || g85 === this.globals || h85 instanceof VeraFunctionType || h85 instanceof VeraClassType || h85 instanceof NamespaceType) {
                this.addError('E2010', 'invalid assignment target', f85.span);
                return VOID;
            }
            return h85;
        }
        if (f85 instanceof IndexExpression || f85 instanceof SelectExpression)
            return this.checkExpression(f85, g85, null);
        this.addError('E2010', 'invalid assignment target', f85.span);
        return VOID;
    }
    private checkExpression(y84: Expression, z84: Scope, a85: VeraType | null): VeraType {
        let b85: VeraType = VOID;
        if (y84 instanceof IntExpression) {
            if (y84.value > 2147483647)
                this.addError('E2011', 'integer literal exceeds int32 range', y84.span);
            b85 = (a85 !== null && identical(a85, NUMBER)) ? NUMBER : INT;
        }
        else if (y84 instanceof NumberExpression)
            b85 = NUMBER;
        else if (y84 instanceof StringExpression)
            b85 = STRING;
        else if (y84 instanceof BooleanExpression)
            b85 = BOOLEAN;
        else if (y84 instanceof NullExpression)
            b85 = NULL_TYPE;
        else if (y84 instanceof NameExpression) {
            let e85 = z84.find(y84.name);
            if (e85 !== null)
                b85 = e85;
            else {
                b85 = VOID;
                this.addError('E2012', 'unknown name ' + y84.name, y84.span);
            }
        }
        else if (y84 instanceof ArrayExpression)
            b85 = this.checkArray(y84, z84, a85);
        else if (y84 instanceof ObjectExpression)
            b85 = this.checkObject(y84, z84, a85);
        else if (y84 instanceof UnaryExpression)
            b85 = this.checkUnary(y84, z84);
        else if (y84 instanceof BinaryExpression)
            b85 = this.checkBinary(y84, z84);
        else if (y84 instanceof IndexExpression) {
            let d85 = this.checkExpression(y84.target, z84, null);
            this.requireType(this.checkExpression(y84.index, z84, INT), INT, y84.index);
            if (d85 instanceof VeraArrayType)
                b85 = d85.element;
            else
                this.addError('E2013', 'index target must be an array', y84.target.span);
        }
        else if (y84 instanceof SelectExpression)
            b85 = this.checkSelect(y84, z84);
        else if (y84 instanceof EnsureNotNullExpression) {
            let c85 = this.checkExpression(y84.operand, z84, null);
            if (c85 instanceof NullableType)
                b85 = c85.base;
            else {
                this.addError('E2041', 'ensure-not-null requires a nullable value', y84.span);
                b85 = c85;
            }
        }
        else if (y84 instanceof CallExpression)
            b85 = this.checkCall(y84, z84, false);
        else if (y84 instanceof AwaitExpression) {
            if (!this.inAsyncFunction)
                this.addError('E2014', 'await is valid only in an async function', y84.span);
            if (!(y84.operand instanceof CallExpression)) {
                this.addError('E2015', 'await requires an async function call', y84.span);
                b85 = VOID;
            }
            else
                b85 = this.checkCall(y84.operand, z84, true);
        }
        else if (y84 instanceof LambdaExpression)
            b85 = this.checkLambda(y84, z84);
        this.model.expressionTypes.set(y84, b85);
        if (a85 !== null && !assignable(b85, a85))
            this.typeError(y84, a85, b85);
        return b85;
    }
    private checkArray(t84: ArrayExpression, u84: Scope, v84: VeraType | null): VeraType {
        let w84 = v84 instanceof NullableType ? v84.base : v84;
        if (!(w84 instanceof VeraArrayType)) {
            this.addError('E2020', 'array literal requires array context', t84.span);
            return new VeraArrayType(VOID);
        }
        for (let x84 of t84.elements)
            this.checkExpression(x84, u84, w84.element);
        return w84;
    }
    private checkObject(k84: ObjectExpression, l84: Scope, m84: VeraType | null): VeraType {
        let n84 = m84 instanceof NullableType ? m84.base : m84;
        if (!(n84 instanceof VeraClassType)) {
            this.addError('E2021', 'object literal requires class context', k84.span);
            return VOID;
        }
        let o84 = new Set<string>();
        for (let r84 of k84.properties) {
            let s84 = n84.fields.get(r84.name);
            if (s84 === undefined)
                this.addError('E2022', 'unknown field ' + r84.name, r84.span);
            else
                this.checkExpression(r84.value, l84, s84);
            if (o84.has(r84.name))
                this.addError('E2023', 'duplicate property ' + r84.name, r84.span);
            o84.add(r84.name);
        }
        let p84 = Array.from(n84.fields.keys());
        for (let q84 of p84) {
            if (!o84.has(q84))
                this.addError('E2024', 'missing field ' + q84, k84.span);
        }
        return n84;
    }
    private checkUnary(h84: UnaryExpression, i84: Scope): VeraType {
        if (h84.operator === '-' && h84.operand instanceof IntExpression && h84.operand.value === 2147483648) {
            this.model.expressionTypes.set(h84.operand, INT);
            return INT;
        }
        let j84 = this.checkExpression(h84.operand, i84, null);
        if (h84.operator === '!') {
            this.requireType(j84, BOOLEAN, h84.operand);
            return BOOLEAN;
        }
        if (!identical(j84, INT) && !identical(j84, NUMBER))
            this.addError('E2025', 'unary minus requires int or number', h84.span);
        return j84;
    }
    private checkBinary(y83: BinaryExpression, z83: Scope): VeraType {
        let a84 = this.checkExpression(y83.left, z83, null);
        let b84 = this.checkExpression(y83.right, z83, null);
        let c84 = y83.operator;
        if (c84 === '===' || c84 === '!==') {
            let e84 = this.isNullableNullPair(a84, b84) || this.isNullableNullPair(b84, a84);
            let f84 = a84 instanceof PrimitiveType && identical(a84, b84) && !identical(a84, VOID);
            let g84 = a84 instanceof VeraFunctionType && b84 instanceof VeraFunctionType && (subtypeOf(a84, b84) || subtypeOf(b84, a84));
            if (!e84 && !f84 && !g84)
                this.addError('E2026', 'unsupported equality operands', y83.span);
            return BOOLEAN;
        }
        if (c84 === '&&' || c84 === '||') {
            this.requireType(a84, BOOLEAN, y83.left);
            this.requireType(b84, BOOLEAN, y83.right);
            return BOOLEAN;
        }
        if (c84 === '<' || c84 === '<=' || c84 === '>' || c84 === '>=') {
            if ((!identical(a84, INT) && !identical(a84, NUMBER) && !identical(a84, STRING)) || !identical(a84, b84)) {
                this.addError('E2027', 'relational operands must be equal int, number, or string types', y83.span);
            }
            return BOOLEAN;
        }
        if (!identical(a84, b84))
            this.addError('E2028', 'arithmetic operands must have identical types', y83.span);
        let d84 = identical(a84, INT) || identical(a84, NUMBER) || (c84 === '+' && identical(a84, STRING));
        if (!d84 || (c84 === '%' && !identical(a84, INT)))
            this.addError('E2029', 'operator ' + c84 + ' is invalid for ' + a84.display(), y83.span);
        return a84;
    }
    private checkSelect(s83: SelectExpression, t83: Scope): VeraType {
        let u83 = this.checkExpression(s83.target, t83, null);
        if (u83 instanceof NamespaceType) {
            let x83 = u83.members.get(s83.field);
            if (x83 === undefined)
                this.addError('E2030', 'namespace has no member ' + s83.field, s83.span);
            return x83 !== undefined ? x83 : VOID;
        }
        if ((u83 instanceof VeraArrayType || identical(u83, STRING)) && s83.field === 'length') {
            return new VeraFunctionType([], INT, false, 'intrinsic:length');
        }
        if (u83 instanceof VeraArrayType) {
            let w83 = (u83 as VeraArrayType).element;
            if (s83.field === 'push') {
                return new VeraFunctionType([w83], INT, false, 'intrinsic:push');
            }
            if (s83.field === 'pop') {
                return new VeraFunctionType([], w83, false, 'intrinsic:pop');
            }
        }
        if (u83 instanceof VeraClassType) {
            let v83 = u83.fields.get(s83.field);
            if (v83 === undefined)
                this.addError('E2031', 'class ' + u83.name + ' has no field ' + s83.field, s83.span);
            return v83 !== undefined ? v83 : VOID;
        }
        if (u83 instanceof NullableType)
            this.addError('E2032', 'nullable value must be narrowed before field access', s83.span);
        else
            this.addError('E2033', 'field selection requires class, array, string, or namespace', s83.span);
        return VOID;
    }
    private checkCall(l83: CallExpression, m83: Scope, n83: boolean): VeraType {
        let o83 = this.checkExpression(l83.callee, m83, null);
        if (!(o83 instanceof VeraFunctionType)) {
            this.addError('E2034', 'callee is not a function', l83.callee.span);
            return VOID;
        }
        if (o83.isAsync !== n83)
            this.addError('E2035', o83.isAsync ? 'async call must be awaited' : 'synchronous call cannot be awaited', l83.span);
        if (l83.argumentsList.length < o83.required ||
            l83.argumentsList.length > o83.parameters.length) {
            let r83 = o83.required === o83.parameters.length
                ? o83.parameters.length.toString()
                : o83.required.toString() + ' to ' + o83.parameters.length.toString();
            this.addError('E2036', 'expected ' + r83 + ' arguments, found ' +
                l83.argumentsList.length, l83.span);
        }
        for (let p83 = 0; p83 < l83.argumentsList.length; p83++) {
            let q83 = p83 < o83.parameters.length ? o83.parameters[p83] : null;
            this.checkExpression(l83.argumentsList[p83], m83, q83);
        }
        this.checkStyleArguments(l83, o83);
        this.checkComposition(l83, o83);
        this.checkSdkArguments(l83, o83);
        return o83.result;
    }
    private checkComposition(y82: CallExpression, z82: VeraFunctionType): void {
        const a83 = 'external:std/ui:';
        if (!z82.identity.startsWith(a83))
            return;
        let b83 = z82.identity.substring(a83.length);
        let c83: ChildRule | null = childRuleFor(b83);
        if (c83 === null)
            return;
        if (c83!.allowed.length > 0) {
            for (let g83 of CATALOG) {
                if (g83.name !== b83)
                    continue;
                for (let h83 = 0; h83 < g83.props.length && h83 < y82.argumentsList.length; h83++) {
                    if (g83.props[h83].kind !== 'view[]')
                        continue;
                    let i83 = y82.argumentsList[h83];
                    if (!(i83 instanceof ArrayExpression))
                        break;
                    for (let j83 of (i83 as ArrayExpression).elements) {
                        let k83 = this.uiComponentName(j83);
                        if (k83.length === 0)
                            continue;
                        if (c83!.allowed.indexOf(k83) < 0) {
                            this.addError('E2107', b83 + ' takes only ' + listWords(c83!.allowed) +
                                ' children, not ' + k83, j83.span);
                        }
                    }
                    break;
                }
                break;
            }
        }
        for (let d83 of c83!.refusedInside) {
            for (let e83 of y82.argumentsList) {
                let f83 = this.findUiDescendant(e83, d83);
                if (f83 !== null) {
                    this.addError('E2107', b83 + ' may not contain another ' + d83, f83!.span);
                    break;
                }
            }
        }
    }
    private uiComponentName(u82: Expression): string {
        if (!(u82 instanceof CallExpression))
            return '';
        let v82 = (u82 as CallExpression).callee;
        if (!(v82 instanceof SelectExpression))
            return '';
        let w82 = (v82 as SelectExpression).field;
        if (w82 === 'When')
            return 'When';
        for (let x82 of CATALOG) {
            if (x82.name === w82)
                return w82;
        }
        return '';
    }
    private findUiDescendant(o82: Expression, p82: string): Expression | null {
        if (o82 instanceof ArrayExpression) {
            for (let s82 of (o82 as ArrayExpression).elements) {
                let t82 = this.findUiDescendant(s82, p82);
                if (t82 !== null)
                    return t82;
            }
            return null;
        }
        if (o82 instanceof CallExpression) {
            if (this.uiComponentName(o82) === p82)
                return o82;
            for (let q82 of (o82 as CallExpression).argumentsList) {
                let r82 = this.findUiDescendant(q82, p82);
                if (r82 !== null)
                    return r82;
            }
        }
        return null;
    }
    private checkStyleArguments(f82: CallExpression, g82: VeraFunctionType): void {
        const h82 = 'external:std/ui:';
        if (!g82.identity.startsWith(h82))
            return;
        let i82 = g82.identity.substring(h82.length);
        for (let j82 of CATALOG) {
            if (j82.name !== i82)
                continue;
            for (let k82 = 0; k82 < j82.props.length && k82 < f82.argumentsList.length; k82++) {
                let l82 = j82.props[k82];
                if (l82.styleSet.length === 0)
                    continue;
                let m82 = f82.argumentsList[k82];
                if (!(m82 instanceof StringExpression))
                    continue;
                let n82 = stylesFor(j82.nodeKind);
                if (n82.length === 0)
                    continue;
                if (n82.indexOf((m82 as StringExpression).value) < 0) {
                    this.addError('E2105', 'unknown ' + j82.name + ' style "' + (m82 as StringExpression).value +
                        '"; allowed: ' + n82.join(' '), m82.span);
                }
            }
            this.checkIconArguments(f82, j82);
            this.checkHandlerSignature(f82, j82);
            return;
        }
    }
    private checkIconArguments(a82: CallExpression, b82: ComponentSpec): void {
        for (let c82 = 0; c82 < b82.props.length && c82 < a82.argumentsList.length; c82++) {
            if (b82.props[c82].kind !== 'icon')
                continue;
            let d82 = a82.argumentsList[c82];
            if (!(d82 instanceof StringExpression))
                continue;
            let e82 = (d82 as StringExpression).value;
            if (e82.length === 0)
                continue;
            if (iconPath(e82).length === 0) {
                this.addError('E2108', 'unknown icon "' + e82 + '"; the icons are: ' +
                    iconNames().join(' '), d82.span);
            }
        }
    }
    private checkSdkArguments(l81: CallExpression, m81: VeraFunctionType): void {
        if (m81.identity !== 'external:std/sdk:call')
            return;
        if (l81.argumentsList.length > 0 && l81.argumentsList[0] instanceof StringExpression) {
            let v81 = l81.argumentsList[0];
            let w81 = (v81 as StringExpression).value;
            if (w81.indexOf('/') >= 0) {
                let x81 = w81.split('/');
                let y81 = false;
                for (let z81 of x81) {
                    if (z81.trim().length === 0) {
                        y81 = true;
                    }
                }
                if ((x81.length !== 4 && x81.length !== 3) || y81) {
                    this.addError('E2109', 'an intent-style sdk.call target must be ' +
                        '"bundle/module/ability/IntentName", or "bundle/module/ability" to just launch it; got "' + w81 + '"', v81.span);
                }
            }
            else if (!isValidSdkTarget(w81)) {
                this.addError('E2110', 'sdk.call target "' + w81 + '" is not one find_sdk_function ' +
                    'returned; call it first and use a target exactly as it came back', v81.span);
            }
        }
        if (l81.argumentsList.length > 1 && l81.argumentsList[1] instanceof ArrayExpression) {
            let s81 = l81.argumentsList[1];
            let t81 = (s81 as ArrayExpression).elements;
            if (t81.length % 2 !== 0) {
                this.addError('E2111', 'sdk.call parameters are name and value in pairs, so the ' +
                    'array must have an even number of items; got ' + t81.length.toString(), s81.span);
            }
            for (let u81 = 0; u81 + 1 < t81.length; u81 = u81 + 2) {
                if (!(t81[u81] instanceof StringExpression)) {
                    continue;
                }
                if ((t81[u81] as StringExpression).value.trim().length === 0) {
                    this.addError('E2111', 'sdk.call parameter names cannot be empty', t81[u81].span);
                }
            }
        }
        if (l81.argumentsList.length > 3 && l81.argumentsList[3] instanceof StringExpression) {
            let q81 = l81.argumentsList[3];
            let r81 = (q81 as StringExpression).value;
            if (r81 !== 'foreground' && r81 !== 'background') {
                this.addError('E2109', 'sdk.call mode must be "foreground" or "background"; got "' + r81 + '"', q81.span);
            }
        }
        if (l81.argumentsList.length < 3 || !(l81.argumentsList[2] instanceof StringExpression))
            return;
        let n81 = l81.argumentsList[2];
        let o81 = (n81 as StringExpression).value;
        let p81 = this.model.functions.get(o81);
        if (p81 === undefined) {
            this.addError('E2106', 'no handler named "' + o81 + '"', n81.span);
            return;
        }
        if (p81.parameters.length < 2 || !identical(p81.parameters[1], STRING)) {
            this.addError('E2106', 'sdk.call answers with a string, so "' + o81 +
                '" must take (state, value: string)', n81.span);
        }
    }
    private checkHandlerSignature(c81: CallExpression, d81: ComponentSpec): void {
        let e81 = payloadKindFor(d81.nodeKind);
        if (e81.length === 0)
            return;
        for (let f81 = 0; f81 < d81.props.length && f81 < c81.argumentsList.length; f81++) {
            if (d81.props[f81].name !== 'action')
                continue;
            let g81 = c81.argumentsList[f81];
            if (!(g81 instanceof StringExpression))
                return;
            let h81 = (g81 as StringExpression).value;
            let i81 = this.model.functions.get(h81);
            if (i81 === undefined) {
                this.addError('E2106', 'no handler named "' + h81 + '"', g81.span);
                return;
            }
            let j81: VeraType = e81 === 'string' ? STRING : e81 === 'boolean' ? BOOLEAN : INT;
            if (i81.parameters.length < 2 || !identical(i81.parameters[1], j81)) {
                let k81 = e81 === 'int' ? 'an ' : 'a ';
                this.addError('E2106', d81.name + ' hands its handler ' + k81 + e81 + ', so "' + h81 + '" must take (state, value: ' + e81 + ')', g81.span);
            }
            return;
        }
    }
    private checkLambda(q80: LambdaExpression, r80: Scope): VeraType {
        let s80: VeraType[] = [];
        for (let b81 of q80.parameters)
            s80.push(this.resolveType(b81.type));
        let t80 = this.resolveType(q80.returnType);
        let u80 = new VeraFunctionType(s80, t80, false, 'lambda:' + this.lambdaCount++);
        let v80 = new Scope(r80);
        for (let z80 = 0; z80 < q80.parameters.length; z80++) {
            let a81 = q80.parameters[z80];
            if (v80.find(a81.name) !== null)
                this.addError('E2004', 'declaration ' + a81.name + ' shadows a visible entity', a81.span);
            else
                v80.values.set(a81.name, s80[z80]);
        }
        let w80 = this.returnType;
        let x80 = this.inAsyncFunction;
        this.returnType = t80;
        this.inAsyncFunction = false;
        let y80 = this.checkBlock(q80.body, v80);
        this.returnType = w80;
        this.inAsyncFunction = x80;
        if (!identical(t80, VOID) && !y80)
            this.addError('E2018', 'lambda may not return a value', q80.body.span);
        return u80;
    }
    private narrow(i80: Expression, j80: Scope): Narrowing {
        let k80 = new Scope(j80);
        let l80 = new Scope(j80);
        if (i80 instanceof BinaryExpression) {
            let m80 = i80.operator;
            if (m80 !== '===' && m80 !== '!==')
                return new Narrowing(k80, l80);
            let n80: NameExpression | null = null;
            if (i80.left instanceof NameExpression && i80.right instanceof NullExpression)
                n80 = i80.left;
            else if (i80.right instanceof NameExpression && i80.left instanceof NullExpression)
                n80 = i80.right;
            if (n80 !== null) {
                let o80 = j80.find(n80.name);
                if (o80 !== null && o80 instanceof NullableType) {
                    let p80 = m80 === '!==' ? k80 : l80;
                    p80.values.set(n80.name, o80.base);
                }
            }
        }
        return new Narrowing(k80, l80);
    }
    resolveType(d80: TypeNode): VeraType {
        let e80 = this.model.declaredTypes.get(d80);
        if (e80 !== undefined)
            return e80;
        let f80: VeraType;
        if (d80.name === 'int')
            f80 = INT;
        else if (d80.name === 'number')
            f80 = NUMBER;
        else if (d80.name === 'boolean')
            f80 = BOOLEAN;
        else if (d80.name === 'string')
            f80 = STRING;
        else if (d80.name === 'void')
            f80 = VOID;
        else if (d80.name === 'array')
            f80 = new VeraArrayType(this.resolveType(d80.parts[0]));
        else if (d80.name === 'function' || d80.name === 'async-function') {
            let g80: VeraType[] = [];
            for (let h80 of d80.parts)
                g80.push(this.resolveType(h80));
            f80 = new VeraFunctionType(g80.slice(0, -1), g80[g80.length - 1], d80.name === 'async-function', 'function-type');
        }
        else
            f80 = this.resolveNamedType(d80.name, d80);
        if (d80.nullable) {
            if (identical(f80, VOID))
                this.addError('E2037', 'void cannot be nullable', d80.span);
            f80 = new NullableType(f80);
        }
        this.model.declaredTypes.set(d80, f80);
        return f80;
    }
    private resolveNamedType(x79: string, y79: TypeNode): VeraType {
        let z79 = x79.split('.');
        let a80: VeraType | null = this.globals.find(z79[0]);
        for (let b80 = 1; b80 < z79.length; b80++) {
            if (a80 instanceof NamespaceType) {
                let c80 = a80.members.get(z79[b80]);
                a80 = c80 !== undefined ? c80 : null;
            }
            else {
                a80 = null;
            }
        }
        if (!(a80 instanceof VeraClassType)) {
            this.addError('E2038', 'unknown class type ' + x79, y79.span);
            return VOID;
        }
        return a80;
    }
    private isNullableNullPair(v79: VeraType, w79: VeraType): boolean {
        return v79 instanceof NullableType && w79 instanceof VeraNullType;
    }
    private requireType(s79: VeraType, t79: VeraType, u79: Expression): void {
        if (!identical(s79, t79))
            this.typeError(u79, t79, s79);
    }
    private typeError(p79: Expression, q79: VeraType, r79: VeraType): void {
        this.diagnostics.push(new Diagnostic('E2019', 'expected ' + q79.display() + ', found ' + r79.display(), p79.span, q79.display(), r79.display()));
    }
    private addError(m79: string, n79: string, o79: Span): void {
        this.diagnostics.push(new Diagnostic(m79, n79, o79));
    }
}
class Binding {
    location: string;
    slot: number;
    constructor(k79: string, l79: number) { this.location = k79; this.slot = l79; }
}
class LoopLabels {
    breaks: number[];
    continues: number[];
    continueTarget: number;
    constructor(h79: number[], i79: number[], j79: number) {
        this.breaks = h79;
        this.continues = i79;
        this.continueTarget = j79;
    }
}
class FunctionBuilder {
    instructions: Instruction[] = [];
    bindings: Map<string, Binding> = new Map<string, Binding>();
    capturedBindings: Map<string, number> = new Map<string, number>();
    loops: LoopLabels[] = [];
    localCount: number = 0;
    name: string;
    parent: FunctionBuilder | null;
    constructor(f79: string, g79: FunctionBuilder | null) {
        this.name = f79;
        this.parent = g79;
    }
    emit(e79: Instruction): number {
        this.instructions.push(e79);
        return this.instructions.length - 1;
    }
    local(c79: string): number {
        let d79 = this.localCount++;
        this.bindings.set(c79, new Binding('local', d79));
        return d79;
    }
}
function mkInst(b79: string): Instruction { return new Instruction(b79); }
function mkPushInt(z78: string): Instruction { let a79 = mkInst('push-int'); a79.value = z78; return a79; }
function mkPushNumber(x78: number): Instruction { let y78 = mkInst('push-number'); y78.numValue = x78; return y78; }
function mkPushString(v78: string): Instruction { let w78 = mkInst('push-string'); w78.value = v78; return w78; }
function mkPushBoolean(t78: boolean): Instruction { let u78 = mkInst('push-boolean'); u78.boolValue = t78; return u78; }
function mkLoadLocal(r78: number): Instruction { let s78 = mkInst('load-local'); s78.slot = r78; return s78; }
function mkStoreLocal(p78: number): Instruction { let q78 = mkInst('store-local'); q78.slot = p78; return q78; }
function mkLoadCapture(n78: number): Instruction { let o78 = mkInst('load-capture'); o78.slot = n78; return o78; }
function mkStoreCapture(l78: number): Instruction { let m78 = mkInst('store-capture'); m78.slot = l78; return m78; }
function mkLoadFunction(j78: string): Instruction { let k78 = mkInst('load-function'); k78.name = j78; return k78; }
function mkLoadExternal(g78: string, h78: string): Instruction { let i78 = mkInst('load-external'); i78.module = g78; i78.name = h78; return i78; }
function mkUnary(e78: string): Instruction { let f78 = mkInst('unary'); f78.operator = e78; return f78; }
function mkBinary(b78: string, c78: boolean): Instruction { let d78 = mkInst('binary'); d78.operator = b78; d78.integer = c78; return d78; }
function mkJump(z77: number): Instruction { let a78 = mkInst('jump'); a78.target = z77; return a78; }
function mkJumpIfFalse(x77: number): Instruction { let y77 = mkInst('jump-if-false'); y77.target = x77; return y77; }
function mkCall(u77: number, v77: boolean): Instruction { let w77 = mkInst('call'); w77.count = u77; w77.awaited = v77; return w77; }
function mkMakeArray(s77: number): Instruction { let t77 = mkInst('make-array'); t77.count = s77; return t77; }
function mkMakeObject(p77: string, q77: string[]): Instruction {
    let r77 = mkInst('make-object');
    r77.classIdentity = p77;
    r77.fields = q77;
    return r77;
}
function mkLoadField(n77: string): Instruction { let o77 = mkInst('load-field'); o77.name = n77; return o77; }
function mkStoreField(l77: string): Instruction { let m77 = mkInst('store-field'); m77.name = l77; return m77; }
function mkMakeClosure(i77: string, j77: number[]): Instruction {
    let k77 = mkInst('make-closure');
    k77.functionName = i77;
    k77.captures = j77;
    return k77;
}
class BytecodeCompiler {
    private functions: BytecodeFunction[] = [];
    private lambdaCount: number = 0;
    private model: SemanticModel;
    constructor(h77: SemanticModel) { this.model = h77; }
    compile(): BytecodeModule {
        for (let g77 of this.model.application.declarations) {
            if (g77 instanceof FunctionDeclaration)
                this.compileFunction(g77);
        }
        let d77: string[] = [];
        let e77 = Array.from(this.model.functions.keys());
        for (let f77 of e77)
            d77.push(f77);
        return new BytecodeModule(this.functions, d77);
    }
    private compileFunction(a77: FunctionDeclaration): void {
        let b77 = new FunctionBuilder(a77.name, null);
        for (let c77 of a77.parameters)
            b77.local(c77.name);
        this.block(a77.body, b77);
        b77.emit(mkInst('push-null'));
        b77.emit(mkInst('return'));
        this.functions.push(new BytecodeFunction(a77.name, a77.parameters.length, b77.localCount, a77.isAsync, b77.instructions));
    }
    private block(x76: BlockStatement, y76: FunctionBuilder): void {
        for (let z76 of x76.statements)
            this.statement(z76, y76);
    }
    private statement(n76: Statement, o76: FunctionBuilder): void {
        if (n76 instanceof BlockStatement)
            this.block(n76, o76);
        else if (n76 instanceof LetStatement) {
            this.expression(n76.initializer, o76);
            o76.emit(mkStoreLocal(o76.local(n76.name)));
        }
        else if (n76 instanceof ExpressionStatement) {
            this.expression(n76.expression, o76);
            o76.emit(mkInst('pop'));
        }
        else if (n76 instanceof AssignStatement)
            this.assignment(n76, o76);
        else if (n76 instanceof ReturnStatement) {
            if (n76.value === null)
                o76.emit(mkInst('push-null'));
            else
                this.expression(n76.value, o76);
            o76.emit(mkInst('return'));
        }
        else if (n76 instanceof IfStatement) {
            this.expression(n76.condition, o76);
            let v76 = o76.emit(mkJumpIfFalse(-1));
            this.block(n76.thenBranch, o76);
            if (n76.elseBranch !== null) {
                let w76 = o76.emit(mkJump(-1));
                this.patch(o76, v76, o76.instructions.length);
                this.statement(n76.elseBranch, o76);
                this.patch(o76, w76, o76.instructions.length);
            }
            else {
                this.patch(o76, v76, o76.instructions.length);
            }
        }
        else if (n76 instanceof WhileStatement) {
            let r76 = o76.instructions.length;
            this.expression(n76.condition, o76);
            let s76 = o76.emit(mkJumpIfFalse(-1));
            let t76 = new LoopLabels([], [], r76);
            o76.loops.push(t76);
            this.block(n76.body, o76);
            o76.emit(mkJump(r76));
            let u76 = o76.instructions.length;
            this.patch(o76, s76, u76);
            this.finishLoop(o76, t76, u76, true);
        }
        else if (n76 instanceof ForOfStatement)
            this.forOf(n76, o76);
        else if (n76 instanceof TryStatement) {
            this.block(n76.tryBlock, o76);
        }
        else if (n76 instanceof BreakStatement) {
            let q76 = o76.loops[o76.loops.length - 1];
            q76.breaks.push(o76.emit(mkJump(-1)));
        }
        else if (n76 instanceof ContinueStatement) {
            let p76 = o76.loops[o76.loops.length - 1];
            p76.continues.push(o76.emit(mkJump(-1)));
        }
    }
    private forOf(c76: ForOfStatement, d76: FunctionBuilder): void {
        let e76 = d76.local('$array' + d76.localCount);
        let f76 = d76.local('$index' + d76.localCount);
        let g76 = d76.local(c76.name);
        this.expression(c76.iterable, d76);
        if (this.model.expressionTypes.get(c76.iterable) === STRING)
            d76.emit(mkInst('string-symbols'));
        d76.emit(mkStoreLocal(e76));
        d76.emit(mkPushInt('0'));
        d76.emit(mkStoreLocal(f76));
        let h76 = d76.instructions.length;
        d76.emit(mkLoadLocal(f76));
        d76.emit(mkLoadLocal(e76));
        d76.emit(mkInst('length'));
        d76.emit(mkBinary('<', true));
        let i76 = d76.emit(mkJumpIfFalse(-1));
        d76.emit(mkLoadLocal(e76));
        d76.emit(mkLoadLocal(f76));
        d76.emit(mkInst('load-index'));
        d76.emit(mkStoreLocal(g76));
        let j76 = new LoopLabels([], [], -1);
        d76.loops.push(j76);
        this.block(c76.body, d76);
        let k76 = d76.instructions.length;
        d76.emit(mkLoadLocal(f76));
        d76.emit(mkPushInt('1'));
        d76.emit(mkBinary('+', true));
        d76.emit(mkStoreLocal(f76));
        d76.emit(mkJump(h76));
        let l76 = d76.instructions.length;
        this.patch(d76, i76, l76);
        let m76 = new LoopLabels(j76.breaks, j76.continues, k76);
        d76.loops.pop();
        this.finishLoop(d76, m76, l76, false);
    }
    private finishLoop(w75: FunctionBuilder, x75: LoopLabels, y75: number, z75: boolean): void {
        if (z75)
            w75.loops.pop();
        for (let b76 of x75.breaks)
            this.patch(w75, b76, y75);
        for (let a76 of x75.continues)
            this.patch(w75, a76, x75.continueTarget);
    }
    private assignment(t75: AssignStatement, u75: FunctionBuilder): void {
        let v75 = t75.target;
        if (v75 instanceof NameExpression) {
            this.expression(t75.value, u75);
            this.storeName(v75.name, u75);
        }
        else if (v75 instanceof IndexExpression) {
            this.expression(v75.target, u75);
            this.expression(v75.index, u75);
            this.expression(t75.value, u75);
            u75.emit(mkInst('store-index'));
        }
        else if (v75 instanceof SelectExpression) {
            this.expression(v75.target, u75);
            this.expression(t75.value, u75);
            u75.emit(mkStoreField(v75.field));
        }
    }
    private expression(j75: Expression, k75: FunctionBuilder): void {
        if (j75 instanceof IntExpression) {
            let s75 = this.model.expressionTypes.get(j75);
            if (s75 !== undefined && identical(s75, NUMBER))
                k75.emit(mkPushNumber(j75.value));
            else
                k75.emit(mkPushInt(j75.value.toString()));
        }
        else if (j75 instanceof NumberExpression)
            k75.emit(mkPushNumber(j75.value));
        else if (j75 instanceof StringExpression)
            k75.emit(mkPushString(j75.value));
        else if (j75 instanceof BooleanExpression)
            k75.emit(mkPushBoolean(j75.value));
        else if (j75 instanceof NullExpression)
            k75.emit(mkInst('push-null'));
        else if (j75 instanceof NameExpression)
            this.loadName(j75.name, k75);
        else if (j75 instanceof UnaryExpression) {
            if (j75.operator === '-' && j75.operand instanceof IntExpression && j75.operand.value === 2147483648) {
                k75.emit(mkPushInt('-2147483648'));
            }
            else {
                this.expression(j75.operand, k75);
                k75.emit(mkUnary(j75.operator));
            }
        }
        else if (j75 instanceof BinaryExpression)
            this.binary(j75, k75);
        else if (j75 instanceof CallExpression) {
            if (j75.callee instanceof SelectExpression && j75.callee.field === 'push' && j75.argumentsList.length === 1 &&
                this.model.expressionTypes.get(j75.callee.target) instanceof VeraArrayType) {
                this.expression(j75.callee.target, k75);
                this.expression(j75.argumentsList[0], k75);
                k75.emit(mkInst('array-push'));
            }
            else if (j75.callee instanceof SelectExpression && j75.callee.field === 'pop' && j75.argumentsList.length === 0 &&
                this.model.expressionTypes.get(j75.callee.target) instanceof VeraArrayType) {
                this.expression(j75.callee.target, k75);
                k75.emit(mkInst('array-pop'));
            }
            else if (j75.callee instanceof SelectExpression && j75.callee.field === 'length' && j75.argumentsList.length === 0) {
                this.expression(j75.callee.target, k75);
                k75.emit(mkInst('length'));
            }
            else {
                this.call(j75, k75, false);
            }
        }
        else if (j75 instanceof AwaitExpression) {
            if (j75.operand instanceof CallExpression)
                this.call(j75.operand, k75, true);
        }
        else if (j75 instanceof ArrayExpression) {
            for (let r75 of j75.elements)
                this.expression(r75, k75);
            k75.emit(mkMakeArray(j75.elements.length));
        }
        else if (j75 instanceof ObjectExpression) {
            for (let q75 of j75.properties)
                this.expression(q75.value, k75);
            let m75 = this.model.expressionTypes.get(j75);
            let n75 = m75 instanceof VeraClassType ? m75.identity : 'invalid';
            let o75: string[] = [];
            for (let p75 of j75.properties)
                o75.push(p75.name);
            k75.emit(mkMakeObject(n75, o75));
        }
        else if (j75 instanceof IndexExpression) {
            this.expression(j75.target, k75);
            this.expression(j75.index, k75);
            k75.emit(mkInst('load-index'));
        }
        else if (j75 instanceof EnsureNotNullExpression) {
            this.expression(j75.operand, k75);
            k75.emit(mkInst('ensure-not-null'));
        }
        else if (j75 instanceof SelectExpression) {
            if (j75.target instanceof NameExpression) {
                let l75 = this.model.imports.get(j75.target.name);
                if (l75 !== undefined) {
                    k75.emit(mkLoadExternal(l75.specifier, j75.field));
                    return;
                }
            }
            this.expression(j75.target, k75);
            k75.emit(mkLoadField(j75.field));
        }
        else if (j75 instanceof LambdaExpression)
            this.lambda(j75, k75);
    }
    private binary(c75: BinaryExpression, d75: FunctionBuilder): void {
        if (c75.operator === '&&') {
            this.expression(c75.left, d75);
            let h75 = d75.emit(mkJumpIfFalse(-1));
            this.expression(c75.right, d75);
            let i75 = d75.emit(mkJump(-1));
            this.patch(d75, h75, d75.instructions.length);
            d75.emit(mkPushBoolean(false));
            this.patch(d75, i75, d75.instructions.length);
            return;
        }
        if (c75.operator === '||') {
            this.expression(c75.left, d75);
            d75.emit(mkUnary('!'));
            let f75 = d75.emit(mkJumpIfFalse(-1));
            this.expression(c75.right, d75);
            let g75 = d75.emit(mkJump(-1));
            this.patch(d75, f75, d75.instructions.length);
            d75.emit(mkPushBoolean(true));
            this.patch(d75, g75, d75.instructions.length);
            return;
        }
        this.expression(c75.left, d75);
        this.expression(c75.right, d75);
        let e75 = this.model.expressionTypes.get(c75.left);
        d75.emit(mkBinary(c75.operator, e75 === INT));
    }
    private call(y74: CallExpression, z74: FunctionBuilder, a75: boolean): void {
        this.expression(y74.callee, z74);
        for (let b75 of y74.argumentsList)
            this.expression(b75, z74);
        z74.emit(mkCall(y74.argumentsList.length, a75));
    }
    private lambda(q74: LambdaExpression, r74: FunctionBuilder): void {
        let s74 = '$lambda' + this.lambdaCount++;
        let t74 = new FunctionBuilder(s74, r74);
        for (let x74 of q74.parameters)
            t74.local(x74.name);
        this.block(q74.body, t74);
        t74.emit(mkInst('push-null'));
        t74.emit(mkInst('return'));
        let u74: number[] = [];
        let v74 = Array.from(t74.capturedBindings.values());
        for (let w74 of v74)
            u74.push(w74);
        this.functions.push(new BytecodeFunction(s74, q74.parameters.length, t74.localCount, false, t74.instructions));
        r74.emit(mkMakeClosure(s74, u74));
    }
    private loadName(h74: string, i74: FunctionBuilder): void {
        let j74 = i74.bindings.get(h74);
        if (j74 !== undefined) {
            if (j74.location === 'local')
                i74.emit(mkLoadLocal(j74.slot));
            else
                i74.emit(mkLoadCapture(j74.slot));
            return;
        }
        if (this.model.functions.has(h74)) {
            i74.emit(mkLoadFunction(h74));
            return;
        }
        let k74 = h74.split('.');
        if (k74.length >= 2) {
            let p74 = this.model.imports.get(k74[0]);
            if (p74 !== undefined) {
                i74.emit(mkLoadExternal(p74.specifier, k74[1]));
                return;
            }
        }
        let l74 = i74.parent;
        if (l74 !== null) {
            let m74 = this.findBinding(h74, l74);
            if (m74 !== null) {
                let n74 = i74.capturedBindings.size;
                let o74 = m74.location === 'local' ? m74.slot : -m74.slot - 1;
                i74.capturedBindings.set(h74, o74);
                i74.bindings.set(h74, new Binding('capture', n74));
                i74.emit(mkLoadCapture(n74));
                return;
            }
        }
        i74.emit(mkLoadFunction(h74));
    }
    private storeName(e74: string, f74: FunctionBuilder): void {
        let g74 = f74.bindings.get(e74);
        if (g74 === undefined)
            throw new Error('compiler invariant');
        if (g74.location === 'local')
            f74.emit(mkStoreLocal(g74.slot));
        else
            f74.emit(mkStoreCapture(g74.slot));
    }
    private findBinding(b74: string, c74: FunctionBuilder): Binding | null {
        let d74 = c74.bindings.get(b74);
        if (d74 !== undefined)
            return d74;
        if (c74.parent !== null)
            return this.findBinding(b74, c74.parent);
        return null;
    }
    private patch(v73: FunctionBuilder, w73: number, x73: number): void {
        let y73 = v73.instructions[w73];
        if (y73.op === 'jump-if-false') {
            let a74 = mkJumpIfFalse(x73);
            v73.instructions[w73] = a74;
        }
        else {
            let z73 = mkJump(x73);
            v73.instructions[w73] = z73;
        }
    }
}
function encodeInstruction(t73: Instruction): Object[] {
    let u73 = t73.op;
    switch (u73) {
        case 'push-int': return [u73, t73.value];
        case 'push-number': return [u73, t73.numValue];
        case 'push-string': return [u73, t73.value];
        case 'push-boolean': return [u73, t73.boolValue];
        case 'push-null': return [u73];
        case 'load-local': return [u73, t73.slot];
        case 'store-local': return [u73, t73.slot];
        case 'load-capture': return [u73, t73.slot];
        case 'store-capture': return [u73, t73.slot];
        case 'load-function': return [u73, t73.name];
        case 'load-external': return [u73, t73.module, t73.name];
        case 'pop': return [u73];
        case 'duplicate': return [u73];
        case 'unary': return [u73, t73.operator];
        case 'binary': return [u73, t73.operator, t73.integer];
        case 'jump': return [u73, t73.target];
        case 'jump-if-false': return [u73, t73.target];
        case 'call': return [u73, t73.count, t73.awaited];
        case 'return': return [u73];
        case 'make-array': return [u73, t73.count];
        case 'array-push': return [u73];
        case 'array-pop': return [u73];
        case 'length': return [u73];
        case 'string-symbols': return [u73];
        case 'ensure-not-null': return [u73];
        case 'load-index': return [u73];
        case 'store-index': return [u73];
        case 'make-object': return [u73, t73.classIdentity, t73.fields];
        case 'load-field': return [u73, t73.name];
        case 'store-field': return [u73, t73.name];
        case 'make-closure': return [u73, t73.functionName, t73.captures];
        default: return [u73];
    }
}
function serializeVbc2(o73: BytecodeModule): string {
    let p73: Object[] = [];
    for (let q73 of o73.functions) {
        let r73: Object[] = [];
        for (let s73 of q73.instructions)
            r73.push(encodeInstruction(s73));
        p73.push([q73.name, q73.parameterCount, q73.localCount, q73.isAsync, r73]);
    }
    return JSON.stringify(['VBC2', o73.entryCandidates, p73]);
}
export class CompileResult {
    vbc2: string;
    constructor(n73: string) { this.vbc2 = n73; }
}
export function compileVeraSource(i73: string, j73: string = '<source>'): CompileResult {
    let k73 = new Parser(i73, j73).parse();
    let l73 = new Analyzer(k73).analyze();
    let m73 = new BytecodeCompiler(l73).compile();
    return new CompileResult(serializeVbc2(m73));
}
