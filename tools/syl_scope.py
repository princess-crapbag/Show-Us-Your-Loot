"""Finds a local used before it is declared — the one class nothing here caught.

THREE OF THESE HAVE SHIPPED.

  * `HideTarget` was called twenty lines above the `local function HideTarget`
    that defined it. The closure captured the global, which was nil, and it
    threw at the moment of the call rather than at load.
  * `container.heading = heading` sat one line above `local container`, so
    AddSection threw on its first call and the settings window drew one heading
    and nothing else. It looked like an empty settings screen, not a crash.
  * `Widgets.CloseOnEscape` reached UI/Tooltips.lua where `Widgets` was not a
    local, at file scope, which would have thrown on load.

`syl_check.py` structurally cannot see any of them: it looks for
`SYL.Module.Member` references that resolve to nothing, and for a bare
`Module.Member` on a module that was never made a local. A local used too early
is neither, so neither rule applies. This is the tool for that class, and it is
why HANDOFF.md carried "luacheck" as an open item.

WHY NOT LUACHECK. luacheck is the right tool and wants a Lua toolchain — Lua,
LuaRocks, and a first-run triage across a hundred files. There is no Lua on
this machine. `luaparser` installs with pip, gives a genuine AST rather than
another regex, and answers the one question that has actually cost time here.
luacheck can still go in CI later; this runs now, locally, before anything
ships.

WHY LEXICAL ORDER IS THE WHOLE POINT. Lua closes over what is in scope at the
moment a function is *created*, not when it is called. A function that
references a name declared later therefore captures the global — nil — and the
error surfaces at the call, somewhere else entirely. So a reference inside a
closure counts, and is checked against what had been declared where that
closure appeared.

EVERY SCOPE HAS TO BE MODELLED OR IT CRIES WOLF. The first draft knew about
blocks and functions but not about parameters or loop variables, and reported
ten findings on a clean codebase — a parameter named `drops` against an
unrelated `local drops` further down the file. All ten were noise. A checker
that is usually wrong is worse than no checker, because it trains you to skim
the output. So parameters, numeric and generic for-loop variables, if/else
branches, while, repeat and do blocks all open scopes here.

Positions come from statements rather than from names: this luaparser version
gives no position for a Name node, and statement granularity is enough to say
"this line uses something declared on a later one".

Imported by syl_check.py, which skips it when luaparser is not installed
rather than failing the whole run.

Not shipped: tools/ is excluded in .pkgmeta.
"""
from __future__ import annotations

try:
    from luaparser import ast, astnodes
except ImportError:  # pragma: no cover - reported by the caller
    ast = None
    astnodes = None

AVAILABLE = ast is not None


def _line(node, default=0):
    """The first source line this node covers, or the earliest of its children."""
    token = getattr(node, "first_token", None)

    if token is not None and getattr(token, "line", None):
        return token.line

    best = None

    for child in ast.walk(node):
        token = getattr(child, "first_token", None)

        if token is not None and getattr(token, "line", None):
            if best is None or token.line < best:
                best = token.line

    return best if best is not None else default


def _arg_names(args):
    """Parameter names, which are locals for the whole body."""
    return {
        arg.id for arg in (args or []) if isinstance(arg, astnodes.Name)
    }


def _names_declared(stmt):
    """The locals this statement adds to the block it is in."""
    if isinstance(stmt, astnodes.LocalFunction):
        return {stmt.name.id}

    if isinstance(stmt, astnodes.LocalAssign):
        return {
            target.id
            for target in stmt.targets
            if isinstance(target, astnodes.Name)
        }

    return set()


def _block_body(block):
    return getattr(block, "body", None) or []


FUNCTION_NODES = ()


def _split(node):
    """Bare names an expression reads, and any closures inside it.

    Closures come back rather than being walked, because one sees what is in
    scope where it appears and needs its own parameters added first.

    `container.heading` reads `container` and names a field; only the value
    side of an index can be an undeclared variable.
    """
    roots = node if isinstance(node, list) else [node]
    roots = [root for root in roots if root is not None]

    names, bodies, skip = set(), [], set()

    # One pass to decide what NOT to count, because ast.walk is flat: skipping
    # a node does not stop the walker reaching its children on its own.
    #
    # That is what made `roll.guid` look like a read of a variable called
    # `guid`. Under dot notation the index is a field name and never a
    # variable; under square brackets — t[k] — it genuinely is one.
    for root in roots:
        for child in ast.walk(root):
            if isinstance(child, FUNCTION_NODES):
                own = _arg_names(getattr(child, "args", None))

                if isinstance(child, astnodes.LocalFunction):
                    own = own | {child.name.id}

                bodies.append((child.body, own))

                for inner in ast.walk(child.body):
                    skip.add(id(inner))

            elif isinstance(child, astnodes.Invoke):
                # `frame:Hide()` names a method on frame. luaparser stores that
                # method as a Name node, identical in shape to a variable read,
                # so without this the checker reports every `x:Foo()` as a use
                # of any local called Foo — and reports it at the call site,
                # which is the one place the reader will not find the mistake.
                #
                # Found by UI/NameSuggest.lua, whose `local function Hide` sits
                # below a `popup:Hide()`. Nothing was wrong with that code. The
                # docstring above is right that one accepted false positive is
                # the end of anybody reading this output, so it is fixed here
                # rather than worked around by renaming the local.
                #
                # Only the method name is skipped. `source` and `args` are real
                # expressions and are still checked, so `Hide():Foo(Hide)` is
                # still caught twice.
                for inner in ast.walk(child.func):
                    skip.add(id(inner))

            elif isinstance(child, astnodes.Index):
                if getattr(child, "notation", None) == astnodes.IndexNotation.DOT:
                    for inner in ast.walk(child.idx):
                        skip.add(id(inner))

            elif isinstance(child, astnodes.Field):
                # `{ drops = {} }` names a key; `{ [k] = 1 }` reads k. Same
                # distinction as dot versus square indexing, one node along.
                if not getattr(child, "between_brackets", False):
                    for inner in ast.walk(child.key):
                        skip.add(id(inner))

    for root in roots:
        for child in ast.walk(root):
            if id(child) in skip:
                continue

            if isinstance(child, astnodes.Name):
                names.add(child.id)

    return names, bodies


def _process(node, scope, pending, findings, path, line):
    """Check one expression: names against scope, closures recursively."""
    names, bodies = _split(node)

    for name in names:
        if name in scope:
            continue

        declared = pending.get(name)

        # Strictly later. The same line is the declaration itself, or the
        # `local x = x` idiom, where the right-hand side means the outer x.
        if declared is not None and declared > line:
            findings.append((path, line, name, declared))

    for body, own in bodies:
        _process_block(_block_body(body), scope | own, pending, findings, path)


def _process_block(stmts, in_scope, pending, findings, path):
    """One block, in statement order. A block is a scope; statements open more."""
    declared_at = {}

    for stmt in stmts:
        for name in _names_declared(stmt):
            declared_at.setdefault(name, _line(stmt))

    scope = set(in_scope)

    # Anything declared later in THIS block is pending for everything above it,
    # including closures created above it — which is the whole point.
    local_pending = dict(pending)

    for name, at in declared_at.items():
        if name not in scope:
            local_pending[name] = at

    for stmt in stmts:
        line = _line(stmt)

        def look(part, _line_=line):
            _process(part, scope, local_pending, findings, path, _line_)

        def descend(block, extra=frozenset()):
            _process_block(
                _block_body(block), scope | set(extra),
                local_pending, findings, path,
            )

        if isinstance(stmt, astnodes.LocalFunction):
            descend(stmt.body, {stmt.name.id} | _arg_names(stmt.args))

        elif isinstance(stmt, (astnodes.Function, astnodes.Method)):
            # `function Utilities.Trim()` reads Utilities.
            look(stmt.name)
            descend(stmt.body, _arg_names(stmt.args))

        elif isinstance(stmt, astnodes.LocalAssign):
            look(stmt.values)

        elif isinstance(stmt, astnodes.Fornum):
            look([stmt.start, stmt.stop, getattr(stmt, "step", None)])
            descend(stmt.body, {stmt.target.id})

        elif isinstance(stmt, astnodes.Forin):
            look(stmt.iter)
            descend(stmt.body, {
                t.id for t in stmt.targets if isinstance(t, astnodes.Name)
            })

        elif isinstance(stmt, astnodes.While):
            look(stmt.test)
            descend(stmt.body)

        elif isinstance(stmt, astnodes.Repeat):
            # Lua scopes the until-test inside the body, so it is checked there.
            descend(stmt.body)

        elif isinstance(stmt, (astnodes.If, astnodes.ElseIf)):
            look(stmt.test)
            descend(stmt.body)

            orelse = getattr(stmt, "orelse", None)

            if isinstance(orelse, (astnodes.If, astnodes.ElseIf)):
                _process_block([orelse], scope, local_pending, findings, path)
            elif orelse is not None:
                descend(orelse)

        elif isinstance(stmt, astnodes.Do):
            descend(stmt.body)

        else:
            look(stmt)

        for name in _names_declared(stmt):
            scope.add(name)
            local_pending.pop(name, None)


def check_source(source, path):
    """Returns [(path, line, name, declared_line)], or None if it will not parse.

    A parse failure is not reported here — syl_check already parses every file
    and says so, and two tools disagreeing about a syntax error is noise.
    """
    if not AVAILABLE:
        return []

    try:
        tree = ast.parse(source)
    except Exception:
        return None

    findings = []

    _process_block(_block_body(tree.body), set(), {}, findings, path)

    return sorted(set(findings), key=lambda f: (f[0], f[1], f[2]))


if AVAILABLE:
    FUNCTION_NODES = (
        astnodes.Function,
        astnodes.LocalFunction,
        astnodes.AnonymousFunction,
        astnodes.Method,
    )
