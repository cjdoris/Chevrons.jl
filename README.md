# » Chevy.jl

[![Project Status: Active – The project has reached a stable, usable state and is being actively developed.](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![Test Status](https://github.com/cjdoris/Chevy.jl/actions/workflows/tests.yml/badge.svg)](https://github.com/cjdoris/Chevy.jl/actions/workflows/tests.yml)
[![Codecov](https://codecov.io/gh/cjdoris/Chevy.jl/branch/main/graph/badge.svg?token=1flP5128hZ)](https://codecov.io/gh/cjdoris/Chevy.jl)

Your `friendly >> chevron >> based` syntax for piping data through multiple
transformations.

All the good ideas from [Chain.jl](https://github.com/jkrumbiegel/Chain.jl) and
[Pipe.jl](https://github.com/oxinabox/Pipe.jl) but with nicer syntax and REPL integration.

Here is a simple example:
```julia-repl
julia> using Chevy, DataFrames, TidierData

julia> Chevy.enable_repl()  # magic to enable Chevy syntax in the REPL

julia> df = DataFrame(name=["John", "Sally", "Roger"], age=[54, 34, 79], children=[0, 2, 4])
3×3 DataFrame
 Row │ name    age    children
     │ String  Int64  Int64
─────┼─────────────────────────
   1 │ John       54         0
   2 │ Sally      34         2
   3 │ Roger      79         4

julia> df >> @filter(age > 40) >> @select(num_children=children, age)
2×2 DataFrame
 Row │ num_children  age
     │ Int64         Int64
─────┼─────────────────────
   1 │            0     54
   2 │            4     79
```

## Installation

This is not a registered package (yet). You can install this package by clicking `]` to
enter the Pkg REPL then do:

```
pkg> add https://github.com/cjdoris/Chevy.jl
```

## Usage

### Getting started

Chevy exports a macro `@chevy` which transforms expressions like `x >> f(y, z)` into
`f(x, y, z)`. These can be chained together, so that
```julia
@chevy Int[] >> push!(5, 2, 4, 3, 1) >> sort!()
```
is equivalent to
```julia
sort!(push!(Int[], 5, 2, 4, 3, 1))
```

In fact we can see exactly what it is transformed to with `@macroexpand`. This is
equivalent code but with intermediate results saved for clarity.
```julia-repl
julia> @macroexpand @chevy Int[] >> push!(5, 2, 4, 3, 1) >> sort!()
quote
    var"##chevy#241" = Int[]
    var"##chevy#242" = push!(var"##chevy#241", 5, 2, 4, 3, 1)
    sort!(var"##chevy#242")
end
```

Furthermore, `@chevy` works recursively, so you can apply it at the top of a code block
and the syntax is applied to the whole block, such as:
```julia
@chevy module MyModule
    function my_function()
        return Int[] >> push!(5, 2, 4, 3, 1) >> sort!()
    end
end
```

If you are using the Julia REPL, you can activate Chevy's REPL mode like
```julia-repl
julia> Chevy.enable_repl()
```
This allows you to use this syntax from the Julia REPL without typing `@chevy` every
time. Use `Chevy.enable_repl(false)` to disable it again. The rest of the examples here
will be from the REPL mode.

### Basic piping syntax with `>>`

Expressions like `x >> f(y, z)` are transformed to insert `x` as an extra first argument
in the function call, like:
```julia-repl
julia> [5,2,4,3,1] >> sort!() >> println()
[1, 2, 3, 4, 5]
```

If you want the argument to appear elsewhere, you can indicate where with `_`:
```julia-repl
julia> [5,2,4,3,1] >> filter!(isodd, _) >> println()
[5, 3, 1]
```

In fact, you can use any expression involving `_`:
```julia-repl
julia> [5,2,4,3,1] >> filter!(isodd, _ .+ 10) >> println()
[15, 13, 11]
```

### Side-effects with `>>>`

Sometimes you want to do something with an intermediate value in the pipeline, but then
continue with the previous value. For this, you can use `x >>> f()` which is transformed
to `tmp = x; f(tmp); tmp`. It is very similar to Chain.jl's `@aside` syntax.

One use for this is to log intermediate values for debugging:
```julia-repl
julia> [5,2,4,3,1] >> filter!(isodd, _) >>> println("x = ", _) >> sum()
x = [5, 3, 1]
9
```

You can assign values, and even use them in later steps:
```julia-repl
julia> 10 >> (_ * 2) >>> (x = _) >> (x^2 - _)
380

julia> x
20
```

It is also useful for functions which mutate the argument but do not return it:
```julia-repl
julia> [5,2,4,3,1] >> popat!(4)
3

julia> [5,2,4,3,1] >>> popat!(4) >> println()
[5, 2, 4, 1]
```

### Piping backwards with `<<`

You can use `<<` to pipe backwards: `f(y) << x` is transformed to `f(x, y)`.

This can be useful as a sort of "inline do-notation":
```julia-repl
julia> write("hello.txt", "ignore this line\nkeep this line!");

julia> (
           "hello.txt"
           >> open()
           << (io -> io >>> readline() >> read(String))
           >> uppercase()
       )
"KEEP THIS LINE!"
```

### Pro tips

If you surround your pipelines with parentheses then you can place each transformation
on a separate line for clarity. This also allows you to easily comment out transformations.

```julia
(
    df
    # >> @filter(age > 40)
    >> @select(nchildren=children, age)
)
```

## API

See the docstrings for more help:
- `@chevy ...`: Transform and executes the given code.
- `chevy(expr)`: Transform the given expression.
- `Chevy.enable_repl(on=true)`: Enable/disable the REPL integration.

## Syntax summary

| Input | Output | Comments |
| ----- | ------ | -------- |
| `x >> f(y)` | `f(x, y)` | Basic piping with `>>`. |
| `x >> f(y, _)` | `f(y, x)` | `_` to specify argument location. |
| `f(y) << x` | `f(x, y)` | Reverse piping with `<<`. |
| `f(y, __) << x` | `f()` | `__` to specify argument location. |
| `x >>> f(y)` | `tmp = x; f(x, y); tmp` | Pass a value through from a previous step. |
