@testmodule Data begin
    using DataFrames

    df1 = DataFrame(
        name = ["John", "Sally", "Roger"],
        age = Float64[54, 34, 79],
        children = [0, 2, 4],
    )
    df1b = DataFrame(number_of_children = [0, 4], age = Float64[54, 79])
end

@testitem "DataFrames" setup = [Data] begin
    using DataFrames
    @test @chevrons(
        Data.df1 >> subset(:age => age -> age .> 40) >>
        select(:children => :number_of_children, :age)
    ) == Data.df1b
end

@testitem "DataFramesMeta" setup = [Data] begin
    using DataFramesMeta
    @test @chevrons(
        Data.df1 >> @subset(:age .> 40) >> @select(:number_of_children = :children, :age)
    ) == Data.df1b
end

@testitem "DataFrameMacros" setup = [Data] begin
    using DataFrameMacros
    @test @chevrons(
        Data.df1 >> @subset(:age > 40) >> @select(:number_of_children = :children, :age)
    ) == Data.df1b
end

@testitem "TidierData" setup = [Data] begin
    using TidierData
    @test @chevrons(
        Data.df1 >> @filter(age > 40) >> @select(number_of_children = children, age)
    ) == Data.df1b
end

@testitem "Query" setup = [Data] begin
    using DataFrames, Query
    @test @chevrons(
        Data.df1 >> @filter(__.age > 40)() >>
        @map({number_of_children = __.children, __.age})() >> DataFrame()
    ) == Data.df1b
end

@testitem "README examples" begin
    using DataFrames, TidierData, Test

    @testset "Basic DataFrame example" begin
        df = DataFrame(
            name = ["John", "Sally", "Roger"],
            age = [54, 34, 79],
            children = [0, 2, 4],
        )
        result = @chevrons df >> @filter(age > 40) >> @select(num_children = children, age)
        @test size(result) == (2, 2)
        @test result.age == [54, 79]
        @test result.num_children == [0, 4]
    end

    @testset "Basic array manipulation" begin
        result = @chevrons Int[] >> push!(5, 2, 4, 3, 1) >> sort!()
        @test result == [1, 2, 3, 4, 5]
    end

    @testset "Filter with isodd" begin
        result = @chevrons [5, 2, 4, 3, 1] >> filter!(isodd, _)
        @test result == [5, 3, 1]
    end

    @testset "Filter with expression involving _" begin
        result = @chevrons [5, 2, 4, 3, 1] >> filter!(isodd, _ .+ 10)
        @test result == [15, 13, 11]
    end

    @testset "Side effects with >>>" begin
        x = 0
        result = @chevrons 10 >> (_ * 2) >>> (x = _) >> (x^2 - _)
        @test result == 380
        @test x == 20
    end

    @testset "Array mutation with >>>" begin
        arr = [5, 2, 4, 3, 1]
        result = @chevrons arr >>> popat!(4)
        @test result == arr  # >>> returns the original array
        @test arr == [5, 2, 4, 1]  # verify mutation worked
    end

    @testset "Backwards piping with <<" begin
        mktempdir() do dir
            path = joinpath(dir, "test.txt")
            write(path, "ignore this line\nkeep this line!")
            result = @chevrons (
                path >> open() << (io -> io >>> readline() >> read(String)) >> uppercase()
            )
            @test result == "KEEP THIS LINE!"
        end
    end
end
