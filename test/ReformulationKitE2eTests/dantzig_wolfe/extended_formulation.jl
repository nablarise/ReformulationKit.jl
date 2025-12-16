using JuMP

struct BinPackingInstance
    nb_items::Int
    nb_bin_profiles::Int
    item_weights::Vector{Int}
    bin_profile_capacities::Vector{Int}
    nb_bins::Vector{Int}
end

struct BinProfile
    id::Int
    items::Vector{Int}
    item_weights::Vector{Int}
    capacity::Int
    nb_bins::Int
end

Base.show(io::IO, bp::BinProfile) = print(io, "#$(bp.id)")

struct MembershipCallback end

abstract type AbstractColumnIndexGenerator end

struct ColumnIndexGenerator <: AbstractColumnIndexGenerator
    subproblem_id::Int # should be the hash.
    item_assigned_cb::Dict{Int, MembershipCallback}
    item_assigned::Function
    cost::Function
end

Base.hash(cig::ColumnIndexGenerator, h::UInt) = hash(cig.subproblem_id, h)
Base.isequal(a::ColumnIndexGenerator, b::ColumnIndexGenerator) = isequal(a.subproblem_id, b.subproblem_id)
Base.show(io::IO, cig::ColumnIndexGenerator) = print(io, "gen#$(cig.subproblem_id)")

function BinProfileFeasiblePatterns(bin_profile::BinProfile)
    item_assigned_membership_cb = Dict{Int,MembershipCallback}(
        item => MembershipCallback() for item in bin_profile.items
    )
    item_assigned_membership_fct = (i -> 1.0 * i)
    cost = (() -> 1.0)
    return [ColumnIndexGenerator(
        bin_profile.id, 
        item_assigned_membership_cb,
        item_assigned_membership_fct,
        cost
    )]
end

function test_e2e_extended_formulation()
    data = BinPackingInstance(
        10, # nb_items
        3, # nb_bin_profiles
        Int[15, 13, 8, 9, 10, 11, 19, 23, 10, 1], # item_weights
        Int[25, 15, 10], # bin_profile_capacities
        Int[3, 1, 2] # nb_bins
    )

    #bin_profile_ids = collect(1:data.nb_bin_profiles)
    bin_profiles = BinProfile[
        BinProfile(
            id, # id
            collect(1:data.nb_items), # items
            data.item_weights, # item_weights
            data.bin_profile_capacities[id], # capacity
            data.nb_bins[id] # nb_bins
        ) for id in 1:data.nb_bin_profiles
    ]

    master = Model()

    @variable(master, λ[sp in bin_profiles, q in BinProfileFeasiblePatterns(sp)] >= 0, Int)

    # Convexity constraint.
    @constraint(master, convexity_lb[sp in bin_profiles], 
        sum(λ[sp, q] for q in BinProfileFeasiblePatterns(sp)) >= 0
    )
    @constraint(master, convexity_ub[sp in bin_profiles],
        sum(λ[sp, q] for q in BinProfileFeasiblePatterns(sp)) <= sp.nb_bins
    )

    # Item assignement covering constraint.
    items = 1:data.nb_items
    @constraint(
        master, 
        assign_item[i in items], 
        sum(q.item_assigned(i) * λ[sp, q] for sp in bin_profiles, q in BinProfileFeasiblePatterns(sp)) >= 1
    )

    # Objective function
    @objective(master, Min, 
        sum(q.cost() * λ[sp, q] for sp in bin_profiles, q in BinProfileFeasiblePatterns(sp))
    )

    println(master)

    return master
end
