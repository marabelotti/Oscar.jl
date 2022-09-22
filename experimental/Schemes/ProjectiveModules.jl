export is_projective, annihilator

using Infiltrator

function intersect(I::MPolyLocalizedIdeal, J::MPolyLocalizedIdeal)
  L = base_ring(I)
  L == base_ring(J) || error("ideals must be defined in the same ring")
  preI = Oscar.pre_saturated_ideal(I)
  preJ = Oscar.pre_saturated_ideal(J) 
  R = base_ring(L)
  K = intersect(I, J)
  return L(K)
end

function intersect(I::MPolyQuoLocalizedIdeal, J::MPolyQuoLocalizedIdeal)
  L = base_ring(I)
  L == base_ring(J) || error("ideals must be defined in the same ring")
  preI = Oscar.pre_image_ideal(I)
  preJ = Oscar.pre_image_ideal(J) 
  R = base_ring(L)
  K = intersect(preI, preJ)
  return L(K)
end

function annihilator(M::SubQuo)
  R = base_ring(M)
  F = FreeMod(R, 1)
  I = ideal(R, [one(R)])
  for v in gens(M)
    h = hom(F, M, [v])
    K, _ = kernel(h)
    # this is a hack, because getindex is broken for K
    g = Oscar.as_matrix(F, ambient_representatives_generators(K))
    I = intersect(I, ideal(R, minors(g, 1)))
  end
  return I
end

iszero(I::Ideal) = all(x->(iszero(x)), gens(I))

@Markdown.doc """
    is_projective(M::SubQuo)

Given a subquotient ``M = (A + B)/B`` over a ring ``R``, test whether 
``M`` is projective and return a pair of maps ``π : Rʳ ↔ M : σ`` 
where ``π`` is a projection onto ``M`` and ``σ`` a section of ``π`` 
so that ``Rʳ ≅ M ⊕ N`` splits as a direct sum via the projector 
``σ ∘ π``.
"""
function is_projective(M::SubQuo; check::Bool=true)
  if check
    iszero(annihilator(M)) || return false, proj, nothing
  end

  ### Assemble a presentation of M over its base ring
  R = base_ring(M)
  r = ngens(M)
  Rr = FreeMod(R, r)
  proj = hom(Rr, M, gens(M))
  K, inc = kernel(proj)
  s = ngens(K)
  Rs = FreeMod(R, s)
  a = compose(hom(Rs, K, gens(K)), inc)
  # This is the presentation matrix
  A = matrix(a)
  X = Spec(R)

  # First clear all units
  for i in 1:nrows(A)
    for j in 1:ncols(A)
      if is_unit(A[i,j]) 
        return _is_projective(A, X, unit_entry=(i,j))
      end
    end
  end

  A1 = ideal(R, [g for g in minors(A, 1) if !iszero(g)])
  one(R) in A1 || return false, proj, nothing
  l = coordinates(one(R), A1)
  X = Spec(R)
  local_data = []
  for g in A1
    L = PrincipalOpenSubset(X, g)
    Ares = map_entries(x->(L(x, check=false)), A)
    success, proj_res, sec_res = _is_projective(Ares)
    if !success 
      return false, proj, nothing
    end
    push!(local_data, (proj_res, sec_res))
  end
end

### This function assumes that the entry aᵢⱼ is a unit in 𝒪(X).
# Row reduction is performed, then the projector is computed 
# recursively for the lower block matrix.
function _is_projective(A::MatrixElem, X::AbsSpec, i::Int, j::Int)
  R = base_ring(A)
  R == OO(X) || error("rings not compatible")

  m = nrows(A)
  n = ncols(A)

  ### perform the row-reduction for the given unit entry
  B = copy(A)
  u = A[i, j]
  uinv = inv(u)
  multiply_row!(B, uinv, i)
  for k in 1:i-1
    add_row!(B, -A[k, j], i, k)
  end
  for k in i+1:nrows(B)
    add_row!(B, -A[k, j], i, k)
  end
  Asub = B[[k for k in 1:m if k != i], [k for k in 1:n if k !=j]]

  ### Assemble the projector
  P = one(MatrixSpace(R, n, n))
  P[j, j] = 0
  for l in 1:n
    l == j && continue
    P[j, l] = -B[i, l]
  end

  ### Harvest the projector on the subspace
  success, Psub = _is_projective(Asub, X)
  !success && return false, P

  Qinc = zero(P)
  for r in 1:j-1
    for s in 1:j-1
      Qinc[r, s] = Psub[r, s]
    end
    for s in j+1:n
      Qinc[r, s] = Psub[r, s-1]
    end
  end
  for r in j+1:n
    for s in 1:j-1
      Qinc[r, s] = Psub[r-1, s]
    end
    for s in j+1:n
      Qinc[r, s] = Psub[r-1, s-1]
    end
  end

  return true, P*Qinc
end

function _is_projective(A::MatElem, X::AbsSpec)
  R = base_ring(A)
  R == OO(X) || error("rings not compatible")

  m = nrows(A)
  n = ncols(A)

  ### Checking for one possible end of recursion: The matrix presents 
  # a free module
  if iszero(A)
    return true, one(MatrixSpace(R, n, n))
  end

  entry_list = [(A[i,j], i, j) for i in 1:m for j in 1:n if !iszero(A[i,j])]
  I = ideal(R, [a[1] for a in entry_list])
  one(R) in I || return false, zero(MatrixSpace(R, n, n))

  c = coordinates(one(R), I)
  involved_entries = [k for k in 1:length(c) if !iszero(c[k])]

  ### Localize at the hypersurfaces given by the involved entries 
  # and collect the local projectors. 
  rec_results = []
  for k in involved_entries
    U = hypersurface_complement(X, entry_list[k][1])
    AU = map_entries(x->(OO(U)(x, check=false)), A)
    push!(rec_results, _is_projective(AU, U, entry_list[k][2], entry_list[k][3]))
    if last(rec_results)[1] == false
      return false, zero(MatrixSpace(R, n, n))
    end
  end

  ### Lift all the local projectors to the top ring and return their 
  # linear combination.
  Q = zero(MatrixSpace(R, n, n))
  for (k, (_, Psub)) in zip(involved_entries, rec_results)
    r = entry_list[k][2]
    s = entry_list[k][3]
    Rloc = base_ring(Psub)
    u = Rloc(entry_list[k][1], check=false)
    Q += c[k] * map_entries(x->(R(lift(x))), u*Psub)
  end

  return true, Q
end

function (R::MPolyRing)(a::MPolyLocalizedRingElem; check::Bool=true)
  isone(numerator(a)) && return denominator(a)
  return divexact(numerator(a), denominator(a))
end

function (R::MPolyQuo)(a::MPolyQuoLocalizedRingElem; check::Bool=true)
  base_ring(R) === base_ring(parent(a)) || error("rings not compatible")
  if check
    all(x->(x in localized_modulus(parent(a))), gens(modulus(R))) || error("no valid coercion")
  end
  isone(lifted_numerator(a)) && return R(lifted_denominator(a))
  return R(lift(divexact(denominator(a), numerator(a))))
end
