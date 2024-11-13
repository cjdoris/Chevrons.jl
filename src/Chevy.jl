module Chevy

export chevy, @chevy

if VERSION ≥ v"1.11"
    eval(Expr(:public, :enable_repl))
end

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
        length(ex.args) == 3 &&
        ex.args[1] isa Symbol &&
        ex.args[1] in (:<<, :>>, :>>>)
    )
        # found a (lhs >> rhs) or (lhs << rhs) or (lhs >>> rhs) expression
        op, lhs, rhs = ex.args
        # recurse on lhs and rhs
        if op == :<<
            lhs2 = chevy(rhs)
            rhs2 = chevy(lhs)
            var = :__
        else
            lhs2 = chevy(lhs)
            rhs2 = chevy(rhs)
            var = :_
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
        subex = sub(tmp, rhs2, var, op == :>>>)
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
"""
macro chevy(ex)
    return esc(chevy(ex))
end

"""
    enable_repl(on::Bool=true)

Enable or disable REPL integration.

When enabled, all commands in the REPL are transformed by [`chevy`](@ref).
"""
function enable_repl(on::Bool = true)
    transforms = Base.active_repl_backend.ast_transforms
    filter!(is_not_chevy, transforms)
    if on
        pushfirst!(transforms, chevy)
    end
    return
end

is_not_chevy(x) = x !== chevy

function recsub(x, f, v::Symbol, multi::Bool = false)
    # directly substitute _
    if f isa Symbol && f == v
        return Some(x)
    end
    # recursively substitute expressions, stopping at the first replacement
    if f isa Expr
        args = Any[nothing for _ in f.args]
        if f.head == :call && length(f.args) ≥ 1
            if length(f.args) ≥ 2 && f.args[2] isa Expr && f.args[2].head == :parameters
                order = [3:length(f.args); 2; 1]
            else
                order = [2:length(f.args); 1]
            end
        else
            order = 1:length(f.args)
        end
        ok = false
        for i in order
            arg = f.args[i]
            if ok && !multi
                arg2 = arg
            else
                arg2 = recsub(x, arg, v, multi)
                if arg2 === nothing
                    arg2 = arg
                else
                    arg2 = something(arg2)
                    ok = true
                end
            end
            args[i] = arg2
        end
        if ok
            return Expr(f.head, args...)
        end
    end
    return nothing
end

function sub(x, f, v::Symbol, multi::Bool = false)
    # first try recursive substitution looking for the first placeholder
    ans = recsub(x, f, v, multi)
    if ans !== nothing
        return something(ans)
    end
    # at this point, the placeholder was not found and we allow some special cases
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
    # macro calls - insert first arg
    if f isa Expr && f.head == :macrocall && length(f.args) ≥ 2
        # f.args[1] is the macro being called
        # f.args[2] is the LineNumberNode where it is called
        return Expr(:macrocall, f.args[1], f.args[2], x, f.args[3:end]...)
    end
    # property access - recurse into LHS
    if f isa Expr && f.head == :. && length(f.args) ≥ 1
        return Expr(:., sub(x, f.args[1], v), f.args[2:end]...)
    end
    # indexing - recurse into LHS
    if f isa Expr && f.head == :ref && length(f.args) ≥ 1
        return Expr(:ref, sub(x, f.args[1], v), f.args[2:end]...)
    end
    # blocks - recurse into last expression
    if f isa Expr && f.head == :block && length(f.args) ≥ 1
        return Expr(:block, f.args[1:(end-1)]..., sub(x, f.args[end], v))
    end
    # give up
    error(
        "Chevy cannot substitute into `$((f))`; expecting `$v` or a function/macro call, indexing or property access.",
    )
end

function truncate(ex)
    return if ex isa Expr
        Expr(ex.head, [x isa Expr ? :.. : x for x in ex.args]...)
    else
        ex
    end
end

end # module Chevy
