############################################
# MvLogNormalDistribution
############################################
# Description:
#   Encodes a multivariate log-normal PDF.
#   Pamameters: vector m (location) and matrix S (scale).
#
#   Reference: Lognormal distributions: theory and aplications; Crow, 1988
############################################

export MvLogNormalDistribution

type MvLogNormalDistribution{dims} <: MultivariateProbabilityDistribution
    m::Vector{Float64} # Location
    S::Matrix{Float64} # Scale

    function MvLogNormalDistribution(m, S)
        (length(m) == size(S,1) == size(S,2)) || error("Dimensions of m and S must agree")
        return new{length(m)}(m, S)
    end
end

MvLogNormalDistribution(; m=[0.0], S=[1.0]) = MvLogNormalDistribution(m, S)

function vague!{dims}(dist::MvLogNormalDistribution{dims})
    dist.m = zeros(dims)
    dist.S = huge*eye(dims)
    return dist
end

vague{dims}(::Type{MvLogNormalDistribution{dims}}) = MvLogNormalDistribution(m=zeros(dims), V=huge*eye(dims))

isProper(dist::MvLogNormalDistribution) = isRoundedPosDef(dist.S) # TODO: verify

function Base.mean(dist::MvLogNormalDistribution)
    if isProper(dist)
        return exp(dist.m + 0.5*diag(dist.S))
    else
        return fill!(similar(dist.m, NaN))
    end
end

Base.mean{dims}(::Type{MvDeltaDistribution{Float64, dims}}, d::MvLogNormalDistribution{dims}) = MvDeltaDistribution(mean(d)) # Definition for post-processing

function Base.cov(dist::MvLogNormalDistribution)
    if isProper(dist)
        dims = size(dist, 1)
        C = zeros(dims, dims)
        for i = 1:dims
            for j = 1:dims
                C[i,j] = exp(dist.m[i] + dist.m[j] + 0.5*(S[i,i] + S[j,j]))*(exp(S[i,j]) - 1.0)
            end
        end
        return C
    else
        return fill!(similar(dist.S, NaN))
    end
end

Base.var(dist::MvLogNormalDistribution) = exp(2.0*dist.m + diag(dist.S)).*(exp(diag(dist.S)) - 1.0)

format(dist::MvLogNormalDistribution) = "logN(μ=$(format(dist.m)), Σ=$(format(dist.s)))"

show(io::IO, dist::MvLogNormalDistribution) = println(io, format(dist))

==(x::MvLogNormalDistribution, y::MvLogNormalDistribution) = (x.m==y.m && x.S==y.S)
