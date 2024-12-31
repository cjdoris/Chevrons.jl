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
    @test @chevy(
        Data.df1 >> subset(:age => age -> age .> 40) >>
        select(:children => :number_of_children, :age)
    ) == Data.df1b
end

@testitem "DataFramesMeta" setup = [Data] begin
    using DataFramesMeta
    @test @chevy(
        Data.df1 >> @subset(:age .> 40) >> @select(:number_of_children = :children, :age)
    ) == Data.df1b
end

@testitem "DataFrameMacros" setup = [Data] begin
    using DataFrameMacros
    @test @chevy(
        Data.df1 >> @subset(:age > 40) >> @select(:number_of_children = :children, :age)
    ) == Data.df1b
end

@testitem "TidierData" setup = [Data] begin
    using TidierData
    @test @chevy(
        Data.df1 >> @filter(age > 40) >> @select(number_of_children = children, age)
    ) == Data.df1b
end

@testitem "Query" setup = [Data] begin
    using DataFrames, Query
    @test @chevy(
        Data.df1 >> @filter(__.age > 40)() >>
        @map({number_of_children = __.children, __.age})() >> DataFrame()
    ) == Data.df1b
end
