# # Demonstration of the Ideal Manual API following user's design

# using JuMP
# using ReformulationKit
# const RK = ReformulationKit


# # ============================================================================
# # Define Pricing Solution Type
# # ============================================================================

# struct BinPackingInstance
#     nb_items::Int
#     nb_bin_profiles::Int
#     item_weights::Vector{Int}
#     bin_profile_capacities::Vector{Int}
#     nb_bins::Vector{Int}
# end

# struct BinProfile
#     id::Int
#     items::Vector{Int}
#     item_weights::Vector{Int}
#     capacity::Int
#     nb_bins::Int
# end

# @pattern BinProfileFeasiblePatterns(bin_profile::BinProfile, subproblem_model) begin
#     @variable(subproblem_model, assign_item[i in bin_profile.items], Bin)
#     @constraint(subproblem_model, sum(bin_profile.item_weights[i] * assign_item[i] for i in bin_profile.items) <= bin_profile.capacity)
#     @cost(subproblem_model, Min, 1.0)
#     @lower_multiplicity 0
#     @upper_multiplicity bin_profile.nb_bins
# end

# function bin_packing_model()
#     data = BinPackingInstance(
#         10, # nb_items
#         3, # nb_bin_profiles
#         Int[15, 13, 8, 9, 10, 11, 19, 23, 10, 1], # item_weights
#         Int[25, 15, 10], # bin_profile_capacities
#         Int[3, 1, 2] # nb_bins
#     )

#     bin_profiles = BinProfile[
#         BinProfile(
#             id, # id
#             collect(1:data.nb_items), # items
#             data.item_weights, # item_weights
#             data.bin_profile_capacities[id], # capacity
#             data.nb_bins[id] # nb_bins
#         ) for id in 1:data.nb_bin_profiles
#     ]

#     master = Model()

#     @variable(master, λ[sp in bin_profiles, q in BinProfileFeasiblePatterns(sp)] >= 0, Int)

#     # Convexity constraint.
#     @constraint(master, convexity_lb[sp in bin_profiles], 
#         sum(λ[sp, q] for q in BinProfileFeasiblePatterns(sp)) >= 0
#     )
#     @constraint(master, convexity_ub[sp in bin_profiles],
#         sum(λ[sp, q] for q in BinProfileFeasiblePatterns(sp)) <= sp.nb_bins
#     )

#     # Item assignement covering constraint.
#     items = 1:data.nb_items
#     @constraint(
#         master, 
#         assign_item[i in items], 
#         sum(q.item_assigned[i] * λ[sp, q] for sp in bin_profiles, q in BinProfileFeasiblePatterns(sp)) >= 1
#     )

#     # Objective function
#     @objective(master, Min, 
#         sum(p.cost * λ[sp, q] for sp in bin_profiles, q in BinProfileFeasiblePatterns(sp))
#     )

# end

# bin_packing_model()


# ######

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

struct ColumnIndexGenerator end

BinProfileFeasiblePatterns(bin_profiles::BinProfile) = [ColumnIndexGenerator()]

function blabla()
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
    return master
end
blabla()
  