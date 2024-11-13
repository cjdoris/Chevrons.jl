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

@testitem "chevy" setup = [Helpers] begin
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
            (
                input = @ex(f(y, __, z; w = 3) << x),
                output = @ex(tmp1 = x, f(y, tmp1, z; w = 3)),
            ),
            # combine >> <<
            (input = @ex(x >> f() << y), output = @ex(tmp2 = y, tmp1 = x, f(tmp2, tmp1))),
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
        ]
        @assert Chevy.tmp_index[] == 0
        Chevy.tmp_index[] = 1
        try
            @test chevy(case.input) == case.output
        finally
            Chevy.tmp_index[] = 0
        end
        @assert Chevy.tmp_index[] == 0
    end
end

@testitem "@chevy" begin
    # most testing happens in the "chevy" test
    @testset "basics" begin
        @test @chevy(1 + 2) == 3
        @test @chevy(Int[] >> push!(4, 2, 3, 5, 1) >> filter!(isodd, _) >> sort!()) ==
            [1, 3, 5]
        @test @chevy(10 >> (_ - __) << 1) == 9
    end
    @testset "side-effects" begin
        x = 0
        # can't put this inside @test because it introduces a new scope
        y = @chevy(10 >>> (x = _) >> (x^2 - _))
        @test y == 90
        @test x == 10
    end
end

@testitem "activate_repl" begin
    orig_backend = try
        Base.active_repl_backend
    catch
        nothing
    end
    mutable struct FakeBackend
        ast_transforms::Vector{Any}
    end
    fake_backend = FakeBackend(Any[1, 2, 3])
    @eval Base active_repl_backend = $fake_backend
    ts = fake_backend.ast_transforms
    @test ts == Any[1, 2, 3]
    try
        Chevy.enable_repl()
        @test ts == Any[chevy, 1, 2, 3]
        Chevy.enable_repl(false)
        @test ts == Any[1, 2, 3]
        Chevy.enable_repl(true)
        @test ts == Any[chevy, 1, 2, 3]
        Chevy.enable_repl()
        @test ts == Any[chevy, 1, 2, 3]
        Chevy.enable_repl(false)
        @test ts == Any[1, 2, 3]
        push!(ts, chevy)
        @test ts == Any[1, 2, 3, chevy]
        Chevy.enable_repl(false)
        @test ts == Any[1, 2, 3]
        @test ts == Any[1, 2, 3]
        push!(ts, chevy)
        @test ts == Any[1, 2, 3, chevy]
        Chevy.enable_repl()
        @test ts == Any[chevy, 1, 2, 3]
    finally
        @eval Base active_repl_backend = $orig_backend
    end
end
