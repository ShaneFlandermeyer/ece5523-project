using FFTW
using LinearAlgebra
using DSP
using Plots
using Statistics
using ProgressMeter
include("pcfm.jl")


function autocorr(x)
  return conv(x, conj.(x[end:-1:1]))
end

function ∇J(B, x, u, l)
  """
  ∇J(B,Bb,x,m,u,a)
  Compute the frequency template error (FTE) and its associated gradient

  # Arguments
  - `B::Array`: M X M Orthogonal basis
  - `x::Vector`: M X 1 phase code vector
  - `u::Vector`: 2M-1 X 1 Frequency template  
  - `l::Integer`: Norm to use for error calculation
  """
  # Oversampled phase code length
  m = size(B, 1)
  # Zero-pad basis matrix to length 2M-1 (for FFT)
  Bb = vcat(B, zeros(m - 1, trunc(Int, size(B, 2))))
  # PCFM representation of the input phase code vector
  s = exp.(im .* B * x)
  # Pad the waveform to length 2M-1
  sb = vcat(s, zeros(m - 1, size(s, 2)))
  # Compute the (normalized) PSD of the PCFM waveform
  sbf = fftshift(fft(sb))
  sbf = sbf ./ maximum(abs.(sbf))
  # FTE calculation
  J = norm(abs.(sbf) .^ 2 .- u, l)
  # Return the error and gradient
  return (J,
    2 / (J) .* transpose(Bb) * imag.(conj.(sb) .* ifft(ifftshift((abs.(sbf) .^ 2 .- u) .* sbf))))
end

function ∇logJ(B, x, u, a, l)
  """
  ∇logJ(B,Bb,x,m,u,a)
  Compute the log frequency template error (log-FTE) and its associated gradient

  # Arguments
  - `B::Array`: M X M Orthogonal basis
  - `x::Vector`: M X 1 phase code vector
  - `u::Vector`: 2M-1 X 1 Frequency template  
  - `a::Integer`: Log base for error computation
  - `l::Integer`: Norm to use for error calculation

  """
  # Oversampled phase code length
  m = size(B, 1)
  # Zero-pad basis matrix to length 2M-1 (for FFT)
  Bb = vcat(B, zeros(m - 1, size(B, 2)))
  # PCFM representation of the input phase code vector
  s = exp.(im .* B * x)
  # Pad the waveform to length 2M-1
  sb = vcat(s, zeros(m - 1, size(s, 2)))
  # Compute the (normalized) PSD of the PCFM waveform
  sbf = fftshift(fft(sb))
  sbf = sbf ./ maximum(abs.(sbf), dims = 1)
  # log-FTE calculation
  J = norm(log.(a, abs.(sbf) .^ 2) .- log.(a, u), l)
  # Return the error and gradient
  return (J,
    (2 / (log(a) * J)) .* transpose(Bb) * imag.(conj.(sb) .* ifft(ifftshift((log.(a, abs.(sbf) .^ 2) .- log.(a, u)) .* sbf))))
end

function profm(u, iter)
  """
  profm(u,iter)

  Iteratively optimize the PSD using alternating projections as described in the
  PRO-FM paper.
  """
  pk = exp.(im .* angle.(ifft(ifftshift(u))))
  for ii = 1:iter
    rk = ifft(ifftshift(abs.(u) .* exp.(im .* angle.(fftshift(fft(pk))))))
    pk = exp.(im .* angle.(rk))
  end
  return pk
end

function optimize(u, nWaveforms, k; a = 10, tol = 1e-5, maxIter = 1000, savePlots = false, filename = "anim_fps60.gif")
  """
  optimize(u,a,tol,maxIter)

  # Arguments
  - `u::Matrix`: 2M-1 X 1 Frequency template
  - `a::Int`: Log base for log-FTE (ignored if regular FTE is used)
  - `tol::Float64`: Tolerance for early stopping
  - `maxIter::Integer`: Maximum number of iterations
  """
  # TODO: Allow the user to decide which optimization method to use

  #Calculate m from u.
  m = trunc(Int, (length(u) + 1) / 2)
  # Get a randomly initialized phase change vector and phase shaping basis
  # functions from PCFM generator
  (_, x, B) = pcfm(m, k, nWaveforms)
  # Gradient descent Parameters
  μ = 0.5
  β = 0.9
  # Store the error at each iteration
  Jvec = ones(maxIter - 1, 1)
  pkOld = 0
  sbf = zeros(length(u), nWaveforms)
  anim = @animate for ii = 1:maxIter
    # Heavy-ball gradient descent
    (J, ∇) = ∇J(B, x, u, 2)
    # (J, ∇) = ∇logJ(B, x, u, a, 2)
    Jvec[ii:end] .= J
    # Update the search direction
    if ii == 1
      pk = ∇
    else
      pk = ∇ .+ β .* pkOld
    end
    # Update x 
    x -= μ .* pk
    # Stopping condition
    if all(abs.(pk .- pkOld) .< tol)
      break
    end
    pkOld = pk
    # Plots
    # Compute and plot the PSD
    s = exp.(im .* B * x)
    sb = vcat(s, zeros(m - 1, nWaveforms))
    sbf = fftshift(fft(sb))
    sbf = mean(sbf, dims = 2)
    sbf = sbf ./ maximum(abs.(sbf), dims = 1)
    p1 = plot(10 * log10.(abs.(sbf) .^ 2), ylim = (-50, 0),
      xlabel = "Sample Index", label = "Actual PSD")
    plot!(10 * log10.(u), ylim = (-50, 0), label = "PSD Template")
    # Compute and plot the autocorrelation
    corr = abs.(autocorr(s)) ./ maximum(abs.(autocorr(s)))
    p2 = plot(10 * log10.(corr), ylim = (-30, 0), xlabel = "Sample Index",
      ylabel = "Magnitude (dB)", label = "Autocorrelation")
    # Compute and plot the current error
    p3 = plot(Jvec, ylim = (0, maximum(Jvec)), xlabel = "Iteration Number", ylabel = "Error", label="Error")
    plot(p1, p2, p3, layout = (3, 1), linewidth = 2)
  end
  if savePlots
    gif(anim, filename, fps = 60)
  end
  s = exp.(im .* B * x)
  return (x, s)

end