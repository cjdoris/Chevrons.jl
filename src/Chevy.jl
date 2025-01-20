module Chevy

export chevy, @chevy

if VERSION ≥ v"1.11"
    eval(Expr(:public, :enable_repl))
end

function enable_repl end

function chevy end

macro chevy end

module Internals

import ..Chevy: enable_repl, chevy, @chevy

const tmp_index = Ref(0)

"""
    tmpsym()

Generate a unique temporary variable name.

In testing this is deterministic.
"""
function tmpsym()
    i = tmp_index[]
    return if i > 0
        tmp_index[] = i + 1
        Symbol(:tmp, i)
    else
        gensym(:chevy)
    end
end

"""
    chevy(ex)

Transforms an expression exactly the way [`@chevy`](@ref) does.
"""
function chevy(ex)
    if (
        ex isa Expr &&
        ex.head == :call &&
        length(ex.args) ≥ 1 &&
        ex.args[1] isa Symbol &&
        ex.args[1] in (:<<, :>>, :>>>)
    )
        nargs = length(ex.args)
        if nargs == 1
            # nullary `>>()` not allowed
            error("Chevy cannot handle zero-argument `$ex`")
        elseif nargs == 2
            # unary `>>(x)` is just `@chevy(x)`
            return chevy(ex.args[2])
        elseif nargs == 3
            # binary (lhs >> rhs) or (lhs << rhs) or (lhs >>> rhs) expression
            op, lhs, rhs = ex.args
        else
            # parse `>>(x, y, z)` as `(x >> y) >> z` (same as `x >> y >> z`)
            @assert nargs ≥ 4
            op = ex.args[1]
            lhs = Expr(:call, op, ex.args[2:end-1]...)
            rhs = ex.args[end]
        end
        # recurse on lhs and rhs
        if op == :<<
            lhs2 = chevy(rhs)
            rhs2 = chevy(lhs)
        else
            lhs2 = chevy(lhs)
            rhs2 = chevy(rhs)
        end
        # construct an answer block
        ans = Expr(:block)
        # temporary variable to assign lhs to
        # in testing we make this deterministic
        tmp = tmpsym()
        # tmp = lhs2
        # If lhs2 is a block then flatten it out so the resulting expression is easier to read.
        if lhs2 isa Expr && lhs2.head == :block && length(lhs2.args) ≥ 1
            append!(ans.args, lhs2.args[1:(end-1)])
            push!(ans.args, Expr(:(=), tmp, lhs2.args[end]))
        else
            push!(ans.args, Expr(:(=), tmp, lhs2))
        end
        # substitute tmp into the rhs
        subex = sub(tmp, rhs2)
        # append this expression to the answer - again flattening if a block
        if subex isa Expr && subex.head == :block
            append!(ans.args, subex.args)
        else
            push!(ans.args, subex)
        end
        # >>> expressions return the lhs value
        if op == :>>>
            push!(ans.args, tmp)
        end
        return ans
    elseif ex isa Expr
        # otherwise recurse into expressions
        return Expr(ex.head, map(chevy, ex.args)...)
    else
        # otherwise no-op
        return ex
    end
end

"""
    @chevy ex

Recursively replace `>>` chained function calls.

- `x >> f(y, z)` becomes `f(x, y, z)`
- `x >> f(y, _, z)` becomes `f(y, x, z)`
- `x >> f(y) >> g(z)` becomes `g(f(x, y), z)`

Also replaces `<<` in the other direction.

- `f(y, z) << x` becomes `f(x, y, z)`
- `f(y, __, z) << x` becomes `f(y, x, z)` (note the double underscore)
- `x >> f(y) << z` becomes `f(z, x, y)`

Also `>>>` can be used to keep the previous value.

- `x >>> f() >> g()` becomes `tmp = x; f(tmp); g(tmp)`
"""
macro chevy(ex)
    return esc(chevy(ex))
end

"""
    enable_repl(on::Bool=true)

Enable or disable REPL integration.

When enabled, all commands in the REPL are transformed by [`chevy`](@ref).

You can call this in your `startup.jl` file.
"""
function enable_repl(on::Bool = true)
    if isdefined(Base, :active_repl_backend) &&
       isdefined(Base.active_repl_backend, :ast_transforms)
        # if the repl is already active, modify it directly
        transforms = Base.active_repl_backend.ast_transforms
    elseif isdefined(Base, :REPL_MODULE_REF) &&
           isassigned(Base.REPL_MODULE_REF) &&
           isdefined(Base.REPL_MODULE_REF[], :repl_ast_transforms)
        # if not, modify the list of default transforms
        transforms = Base.REPL_MODULE_REF[].repl_ast_transforms
    else
        error("Cannot enable Chevy in the REPL.")
    end
    filter!(is_not_chevy, transforms)
    if on
        pushfirst!(transforms, chevy)
    end
    return
end

is_not_chevy(x) = x !== chevy

function sub_placeholder(x, f)
    # directly substitute _/__/___/etc
    if f isa Symbol
        fstr = String(f)
        if fstr == "_"
            return (x, true)
        elseif !isempty(fstr) && all(==('_'), fstr)
            return (Symbol(fstr[2:end]), false)
        end
    end
    # recursively substitute expressions
    if f isa Expr
        args = []
        done = false
        for arg in f.args
            arg2, done2 = sub_placeholder(x, arg)
            done |= done2
            push!(args, arg2)
        end
        return (Expr(f.head, args...), done)
    end
    return (f, false)
end

function sub(x, f)
    # first try recursive substitution looking for the first placeholder
    f, done = sub_placeholder(x, f)
    if done
        # placeholder found, return the transformed expression
        return f
    else
        # the placeholder was not found and we allow some special cases
        return sub_specialcase(x, f)
    end
end

function sub_specialcase(x, f)
    # function calls - insert first arg
    if f isa Expr && f.head == :call && length(f.args) ≥ 1
        # f.args[1] is the function being called
        # f.args[2] is the optional parameter list
        if length(f.args) ≥ 2 && f.args[2] isa Expr && f.args[2].head == :parameters
            return Expr(:call, f.args[1], f.args[2], x, f.args[3:end]...)
        else
            return Expr(:call, f.args[1], x, f.args[2:end]...)
        end
    end
    # do notation - recurse into function call
    if f isa Expr && f.head == :do && length(f.args) ≥ 1
        return Expr(:do, sub_specialcase(x, f.args[1]), f.args[2:end]...)
    end
    # macro calls - insert first arg
    if f isa Expr && f.head == :macrocall && length(f.args) ≥ 2
        # f.args[1] is the macro being called
        # f.args[2] is the LineNumberNode where it is called
        return Expr(:macrocall, f.args[1], f.args[2], x, f.args[3:end]...)
    end
    # property access - recurse into LHS
    if f isa Expr && f.head == :. && length(f.args) ≥ 1
        return Expr(:., sub_specialcase(x, f.args[1]), f.args[2:end]...)
    end
    # indexing - recurse into LHS
    if f isa Expr && f.head == :ref && length(f.args) ≥ 1
        return Expr(:ref, sub_specialcase(x, f.args[1]), f.args[2:end]...)
    end
    # blocks - recurse into last expression
    if f isa Expr && f.head == :block && length(f.args) ≥ 1
        return Expr(:block, f.args[1:(end-1)]..., sub_specialcase(x, f.args[end]))
    end
    # give up
    error(
        "Chevy cannot substitute into `$(truncate(f))`; expecting `_` or a function/macro call, indexing or property access.",
    )
end

function truncate(ex)
    return if ex isa Expr
        Expr(ex.head, [x isa Expr ? :.. : x for x in ex.args]...)
    else
        ex
    end
end

end

end # module Chevy
