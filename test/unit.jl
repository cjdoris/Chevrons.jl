@testmodule Helpers begin
    macro ex(ex...)
        if length(ex) == 1
            ex = ex[1]
        else
            ex = Expr(:block, ex...)
        end
        QuoteNode(nolinenums(ex))
    end
    function nolinenums(ex)
        if ex isa LineNumberNode
            nothing
        elseif ex isa Expr
            Expr(ex.head, map(nolinenums, ex.args)...)
        else
            ex
        end
    end
end

@testitem "chevrons" setup = [Helpers] begin
    using .Helpers: @ex
    @testset "$(case.input)" for case in [
        # noop
        (input = :(x + y), output = :(x + y)),
        # simple >>
        (input = @ex(x >> f()), output = @ex(tmp1 = x, f(tmp1))),
        (input = @ex(x >> f(y)), output = @ex(tmp1 = x, f(tmp1, y))),
        (input = @ex(x >> f(y, z)), output = @ex(tmp1 = x, f(tmp1, y, z))),
        (input = @ex(x >> f(y = 2)), output = @ex(tmp1 = x, f(tmp1, y = 2))),
        (input = @ex(x >> f(; y = 2)), output = @ex(tmp1 = x, f(tmp1; y = 2))),
        (input = @ex(x >> f(_)), output = @ex(tmp1 = x, f(tmp1))),
        (input = @ex(x >> f(_, y)), output = @ex(tmp1 = x, f(tmp1, y))),
        (input = @ex(x >> f(y, _)), output = @ex(tmp1 = x, f(y, tmp1))),
        (input = @ex(x >> f(y, _, z = 2)), output = @ex(tmp1 = x, f(y, tmp1, z = 2))),
        (input = @ex(x >> f(y, _; z = 2)), output = @ex(tmp1 = x, f(y, tmp1; z = 2))),
        # multiple >> >>
        (input = @ex(x >> f() >> g()), output = @ex(tmp1 = x, tmp2 = f(tmp1), g(tmp2))),
        (
            input = @ex(x >> f(y) >> g(z, _)),
            output = @ex(tmp1 = x, tmp2 = f(tmp1, y), g(z, tmp2)),
        ),
        # simple >>>
        (input = @ex(x >>> f(y)), output = @ex(tmp1 = x, f(tmp1, y), tmp1)),
        (input = @ex(x >>> f(y, _)), output = @ex(tmp1 = x, f(y, tmp1), tmp1)),
        # simple <<
        (input = @ex(f() << x), output = @ex(tmp1 = x, f(tmp1))),
        (input = @ex(f(y, z; w = 3) << x), output = @ex(tmp1 = x, f(tmp1, y, z; w = 3))),
        (input = @ex(f(y, _, z; w = 3) << x), output = @ex(tmp1 = x, f(y, tmp1, z; w = 3))),
        # _, __, ___, etc
        (input = @ex(x >> f(__, ___)), output = @ex(tmp1 = x, f(tmp1, _, __))),
        (input = @ex(x >> f(__, ___, _)), output = @ex(tmp1 = x, f(_, __, tmp1))),
        (
            input = @ex(x >> f(__) >> g(___, _) >> h(_, __)),
            output = @ex(tmp1 = x, tmp2 = f(tmp1, _), tmp3 = g(__, tmp2), h(tmp3, _))
        ),
        # combine >> <<
        (input = @ex(x >> f() << y), output = @ex(tmp2 = y, tmp1 = x, f(tmp2, tmp1))),
        (
            input = @ex(x >> f(z, _) << y),
            output = @ex(tmp2 = y, tmp1 = x, f(tmp2, z, tmp1))
        ),
        (
            input = @ex(x >> f(z, __) << y),
            output = @ex(tmp2 = y, tmp1 = x, f(tmp1, z, tmp2))
        ),
        (
            input = @ex(x >> f(z, __, _) << y),
            output = @ex(tmp2 = y, tmp1 = x, f(z, tmp2, tmp1))
        ),
        # substitute the function being called
        (input = @ex(f >> _(x, y)), output = @ex(tmp1 = f, tmp1(x, y))),
        # infix calls
        (input = @ex(x >> +(y)), output = @ex(tmp1 = x, tmp1 + y)),
        (input = @ex(x >> (_ + y)), output = @ex(tmp1 = x, tmp1 + y)),
        (input = @ex(x >> (y + _)), output = @ex(tmp1 = x, y + tmp1)),
        (input = @ex(x >> (y + z)), output = @ex(tmp1 = x, tmp1 + y + z)),
        # property access
        (input = @ex(x >> (_.k)), output = @ex(tmp1 = x, tmp1.k)),
        (input = @ex(x >> f(y).k), output = @ex(tmp1 = x, f(tmp1, y).k)),
        # indexing
        (input = @ex(a >> _[i]), output = @ex(tmp1 = a, tmp1[i])),
        (input = @ex(i >> a[_]), output = @ex(tmp1 = i, a[tmp1])),
        (input = @ex(i >> a[_, j]), output = @ex(tmp1 = i, a[tmp1, j])),
        (input = @ex(i >> a[j, _]), output = @ex(tmp1 = i, a[j, tmp1])),
        (input = @ex(x >> f(y)[]), output = @ex(tmp1 = x, f(tmp1, y)[])),
        (input = @ex(x >> f(y, _)[i, j]), output = @ex(tmp1 = x, f(y, tmp1)[i, j])),
        (input = @ex(x >> z.f(y, _).k[i, j]), output = @ex(tmp1 = x, z.f(y, tmp1).k[i, j])),
        # macro calls
        (input = @ex(x >> @m()), output = @ex(tmp1 = x, @m(tmp1))),
        (input = @ex(x >> @m(y, z)), output = @ex(tmp1 = x, @m(tmp1, y, z))),
        (input = @ex(x >> @m(y, _, z)), output = @ex(tmp1 = x, @m(y, tmp1, z))),
        # do notation
        (input = @ex(x >> f() do y
            z
        end), output = @ex(tmp1 = x, f(tmp1) do y
            z
        end)),
        (input = @ex(x >> f(y, z) do a
            b
        end), output = @ex(tmp1 = x, f(tmp1, y, z) do a
            b
        end)),
        (input = @ex(x >> f(y, _, z) do a
            b
        end), output = @ex(tmp1 = x, f(y, tmp1, z) do a
            b
        end)),
        # unary >>(x) etc
        (input = @ex(>>(x >> f())), output = @ex(tmp1 = x, f(tmp1))),
        (input = @ex(<<(x >> f())), output = @ex(tmp1 = x, f(tmp1))),
        (input = @ex(>>>(x >> f())), output = @ex(tmp1 = x, f(tmp1))),
        # more than two args >>(x, y, z) etc
        (
            input = @ex(>>(x, f(y), g(z, _))),
            output = @ex(tmp1 = x, tmp2 = f(tmp1, y), g(z, tmp2))
        ),
    ]
        @assert Chevrons.Internals.tmp_index[] == 0
        Chevrons.Internals.tmp_index[] = 1
        try
            @test chevrons(case.input) == case.output
        finally
            Chevrons.Internals.tmp_index[] = 0
        end
        @assert Chevrons.Internals.tmp_index[] == 0
    end

    # syntax errors
    @testset "$input" for input in [@ex(x >> y), @ex(x >> [1, 2, 3])]
        @test_throws(
            r"Chevrons cannot substitute into `.*`; expecting `_` or a function/macro call, indexing or property access.",
            chevrons(input)
        )
    end

    # nullary calls
    @testset "$input" for input in [@ex(>>()), @ex(<<()), @ex(>>>())]
        @test_throws(r"Chevrons cannot handle zero-argument `.*`", chevrons(input))
    end
end

@testitem "@chevrons" begin
    # most testing happens in the "chevrons" test
    @testset "basics" begin
        @test @chevrons(1 + 2) == 3
        @test @chevrons(Int[] >> push!(4, 2, 3, 5, 1) >> filter!(isodd, _) >> sort!()) ==
              [1, 3, 5]
        @test @chevrons(10 >> (_ - __) << 1) == 9
    end
    @testset "side-effects" begin
        x = 0
        # can't put this inside @test because it introduces a new scope
        y = @chevrons(10 >>> (x = _) >> (x^2 - _))
        @test y == 90
        @test x == 10
    end
end

@testitem "activate_repl" begin
    using REPL
    @testset "$case" for case in [:active, :default, :none]
        orig_backend = try
            Base.active_repl_backend
        catch
            nothing
        end
        orig_repl = try
            Base.REPL_MODULE_REF[]
        catch
            nothing
        end
        mutable struct FakeBackend
            ast_transforms::Vector{Any}
        end
        if case == :active
            fake_backend = FakeBackend(Any[1, 2, 3])
            fake_repl = REPL
            ts = fake_backend.ast_transforms
        elseif case == :default
            fake_backend = nothing
            fake_repl = Module(:FakeREPL)
            @eval fake_repl repl_ast_transforms = Any[1, 2, 3]
            ts = fake_repl.repl_ast_transforms
        else
            @assert case == :none
            fake_backend = nothing
            fake_repl = Module(:FakeREPL)
            ts = nothing
        end
        @eval Base active_repl_backend = $fake_backend
        Base.REPL_MODULE_REF[] = fake_repl
        try
            if case == :none
                @test_throws r"Cannot enable Chevrons in the REPL." Chevrons.enable_repl()
                @test_throws r"Cannot enable Chevrons in the REPL." Chevrons.enable_repl(
                    true,
                )
                @test_throws r"Cannot enable Chevrons in the REPL." Chevrons.enable_repl(
                    false,
                )
            else
                @test ts == Any[1, 2, 3]
                Chevrons.enable_repl()
                @test ts == Any[chevrons, 1, 2, 3]
                Chevrons.enable_repl(false)
                @test ts == Any[1, 2, 3]
                Chevrons.enable_repl(true)
                @test ts == Any[chevrons, 1, 2, 3]
                Chevrons.enable_repl()
                @test ts == Any[chevrons, 1, 2, 3]
                Chevrons.enable_repl(false)
                @test ts == Any[1, 2, 3]
                push!(ts, chevrons)
                @test ts == Any[1, 2, 3, chevrons]
                Chevrons.enable_repl(false)
                @test ts == Any[1, 2, 3]
                @test ts == Any[1, 2, 3]
                push!(ts, chevrons)
                @test ts == Any[1, 2, 3, chevrons]
                Chevrons.enable_repl()
                @test ts == Any[chevrons, 1, 2, 3]
            end
        finally
            @eval Base active_repl_backend = $orig_backend
            Base.REPL_MODULE_REF[] = orig_repl
        end
    end
end
