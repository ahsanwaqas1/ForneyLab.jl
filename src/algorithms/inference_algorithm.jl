export InferenceAlgorithm, currentInferenceAlgorithm

"""
An `InferenceAlgorithm` specifies the computations for the quantities of interest.
"""
mutable struct InferenceAlgorithm
    id::Symbol
    posterior_factorization::PosteriorFactorization

    # Bookkeeping for faster lookup during assembly
    interface_to_schedule_entry::Dict{Interface, ScheduleEntry}
    target_to_marginal_entry::Dict{Union{Variable, Cluster}, MarginalEntry}

    # Fields for free energy algorithm assembly
    average_energies::Vector{Dict{Symbol, Any}}
    entropies::Vector{Dict{Symbol, Any}}
end

"""
Return currently active `InferenceAlgorithm`.
Create one if there is none.
"""
function currentInferenceAlgorithm()
    try
        return current_inference_algorithm
    catch
        return InferenceAlgorithm()
    end
end

function setCurrentInferenceAlgorithm(algo::InferenceAlgorithm)
     global current_inference_algorithm = algo
end

function InferenceAlgorithm(
    pfz=currentPosteriorFactorization();
    id=Symbol(""))

    setCurrentInferenceAlgorithm(
        InferenceAlgorithm(
            id,
            pfz,
            Dict{Interface, ScheduleEntry}(),
            Dict{Union{Variable, Cluster}, MarginalEntry}(),
            Dict{Symbol, Any}[],
            Dict{Symbol, Any}[]))
end

function interfaceToScheduleEntry(algo::InferenceAlgorithm)
    mapping = Dict{Interface, ScheduleEntry}()
    for (id, pf) in algo.posterior_factorization
        pf_mapping = interfaceToScheduleEntry(pf.schedule)
        merge!(mapping, pf_mapping)
    end

    return mapping
end

function targetToMarginalEntry(algo::InferenceAlgorithm)
    mapping = Dict{Union{Cluster, Variable}, MarginalEntry}()
    for (id, pf) in algo.posterior_factorization
        pf_mapping = targetToMarginalEntry(pf.marginal_table)
        merge!(mapping, pf_mapping)
    end

    return mapping    
end