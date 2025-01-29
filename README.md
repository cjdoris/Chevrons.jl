# » Chevrons.jl

[![Project Status: Active – The project has reached a stable, usable state and is being actively developed.](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![Test Status](https://github.com/cjdoris/Chevrons.jl/actions/workflows/tests.yml/badge.svg)](https://github.com/cjdoris/Chevrons.jl/actions/workflows/tests.yml)
[![Codecov](https://codecov.io/gh/cjdoris/Chevrons.jl/branch/main/graph/badge.svg?token=1flP5128hZ)](https://codecov.io/gh/cjdoris/Chevrons.jl)

Your `friendly >> chevron >> based` syntax for piping data through multiple
transformations.

A [Julia](https://julialang.org/) package with all the good ideas from
[Chain.jl](https://github.com/jkrumbiegel/Chain.jl) and
[Pipe.jl](https://github.com/oxinabox/Pipe.jl), but with nicer syntax and REPL integration.

Here is a simple example:
```julia-repl
julia> using Chevrons, DataFrames, TidierData

julia> Chevrons.enable_repl()  # magic to enable Chevrons syntax in the REPL

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

Quick comparison with similar packages:

| Feature | Chevrons.jl | [Chain.jl](https://github.com/jkrumbiegel/Chain.jl) | [Pipe.jl](https://github.com/oxinabox/Pipe.jl) |
| --- | --- | --- | --- |
| [Piping syntax](#getting-started) | ✔️ (`>>`) | ✔️ (`@chain`) | ✔️ (`\|>`) |
| [Side effects](#side-effects-with-) | ✔️ (`>>>`) | ✔️ (`@aside`) | ❌ |
| [Pipe backwards](#piping-backwards-with-) | ✔️ (`<<`) | ❌ | ❌ |
| [Recursive syntax](#recursive-usage) | ✔️ | ❌ | ❌ |
| [REPL integration](#repl-integration) | ✔️ | ❌ | ❌ |
| Line numbers on errors | ❌ | ✔️ | ❌ |

## Usage

### Installation

Click `]` to enter the Pkg REPL then do:

```
pkg> add Chevrons
```

### Getting started

Chevrons exports a macro `@chevrons` which transforms expressions like `x >> f(y, z)` into
`f(x, y, z)`. These can be chained together, so that
```julia
@chevrons Int[] >> push!(5, 2, 4, 3, 1) >> sort!()
```
is equivalent to
```julia
sort!(push!(Int[], 5, 2, 4, 3, 1))
```

In fact we can see exactly what it is transformed to with `@macroexpand`. This is
equivalent code but with intermediate results saved for clarity.
```julia-repl
julia> @macroexpand @chevrons Int[] >> push!(5, 2, 4, 3, 1) >> sort!()
quote
    var"##chevrons#241" = Int[]
    var"##chevrons#242" = push!(var"##chevrons#241", 5, 2, 4, 3, 1)
    sort!(var"##chevrons#242")
end
```

### REPL integration

If you are using the Julia REPL, you can activate Chevrons's REPL integration like
```julia-repl
julia> Chevrons.enable_repl()
```
This allows you to use this syntax from the Julia REPL without typing `@chevrons` every
time. Use `Chevrons.enable_repl(false)` to disable it again. The rest of the examples here
will be from the REPL.

Also see [this tip](#startup-file) for automatically enabling the REPL integration.

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

You can instead just use regular do-notation:
```
julia> (
           "hello.txt"
           >> open() do io
               io >>> readline() >> read(String)
           end
           >> uppercase()
       )
"KEEP THIS LINE!"
```

### Recursive usage

The `@chevrons` macro works recursively, meaning you can wrap an entire module (or script
or function or any code block) and all `>>`/`>>>`/`<<` expressions will be converted.

For example here is the first example in this README converted to a script:

```julia
using Chevrons, DataFrames, TidierData

@chevrons begin
    df = DataFrame(name=["John", "Sally", "Roger"], age=[54, 34, 79], children=[0, 2, 4])
    df2 = df >> @filter(age > 40) >> @select(num_children=children, age)
    df2 >> println("data:", _)
    df2 >> size >> println("size:", _)
end
```

Or the data manipulation step can be encapsulated as a function like so:

```julia
@chevrons munge(df) = df >> @filter(age > 40) >> @select(num_children=children, age)
```

### Pro tips

#### Parentheses

If you surround your pipelines with parentheses then you can place each transformation
on a separate line for clarity. This also allows you to easily comment out individual
transformations.

```julia
@chevrons (
    df
    # >> @filter(age > 40)
    >> @select(nchildren=children, age),
)
```

Or you can use `>>(x, y, z)` syntax instead of `x >> y >> z` like so:

```julia
@chevrons >>(
    df,
    # @filter(age > 40),
    @select(nchildren=children, age),
)
```

#### Startup file

You can add the following lines to your `startup.jl` file (usually at
`~/.julia/config/startup.jl`) to enable Chevrons's REPL integration automatically:

```julia
if isinteractive()
    try
        using Chevrons
    catch
        @warn "Chevrons not available"
    end
    if @isdefined Chevrons
        Chevrons.enable_repl()
    end
end
```

Chevrons has no dependencies so is safe to add to your global environment - then it will
always be available at the REPL.

## API

See the docstrings for more help:
- `@chevrons ...`: Transform and execute the given code.
- `chevrons(expr)`: Transform the given expression.
- `Chevrons.enable_repl(on=true)`: Enable/disable the REPL integration.
