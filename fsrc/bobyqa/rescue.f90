subroutine rescue(calfun, n, npt, xl, xu, iprint, maxfun, xbase, xpt, &
     &  fval, xopt, gopt, hq, pq, bmat, zmat, ndim, sl, su, nf, delta, &
     &  kopt, vlag, ptsaux, ptsid, w, f, ftarget, &
     & xhist, maxxhist, fhist, maxfhist)

use, non_intrinsic :: consts_mod, only : RP, IK, ZERO, ONE, HALF
use, non_intrinsic :: evaluate_mod, only : evaluate
use, non_intrinsic :: history_mod, only : savehist
use, non_intrinsic :: linalg_mod, only : inprod, matprod, norm, maximum
use, non_intrinsic :: pintrf_mod, only : OBJ

implicit real(RP) (a - h, o - z)
implicit integer(IK) (i - n)

procedure(OBJ) :: calfun
integer(IK), intent(in) :: maxxhist
integer(IK), intent(in) :: maxfhist
integer(IK), intent(in) :: npt
integer(IK), intent(inout) :: nf
real(RP), intent(in) :: xl(n)
real(RP), intent(in) :: xu(n)
real(RP), intent(out) :: xhist(n, maxxhist)
real(RP), intent(out) :: fhist(maxfhist)

! Local variables
real(RP) :: x(n)
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

dimension xbase(*), xpt(npt, *), fval(*), xopt(*), &
& gopt(*), hq(*), pq(*), bmat(ndim, *), zmat(npt, *), sl(*), su(*), &
& vlag(*), ptsaux(2, *), ptsid(*), w(*)
!
!     The arguments N, NPT, XL, XU, IPRINT, MAXFUN, XBASE, XPT, FVAL, XOPT,
!       GOPT, HQ, PQ, BMAT, ZMAT, NDIM, SL and SU have the same meanings as
!       the corresponding arguments of BOBYQB on the entry to RESCUE.
!     NF is maintained as the number of calls of CALFUN so far, except that
!       NF is set to -1 if the value of MAXFUN prevents further progress.
!     KOPT is maintained so that FVAL(KOPT) is the least calculated function
!       value. Its correct value must be given on entry. It is updated if a
!       new least function value is found, but the corresponding changes to
!       XOPT and GOPT have to be made later by the calling program.
!     DELTA is the current trust region radius.
!     VLAG is a working space vector that will be used for the values of the
!       provisional Lagrange functions at each of the interpolation points.
!       They are part of a product that requires VLAG to be of length NDIM.
!     PTSAUX is also a working space array. For J=1,2,...,N, PTSAUX(1,J) and
!       PTSAUX(2,J) specify the two positions of provisional interpolation
!       points when a nonZERO step is taken along e_J (the J-th coordinate
!       direction) through XBASE+XOPT, as specified below. Usually these
!       steps have length DELTA, but other lengths are chosen if necessary
!       in order to satisfy the given bounds on the variables.
!     PTSID is also a working space array. It has NPT compONEnts that denote
!       provisional new positions of the original interpolation points, in
!       case changes are needed to restore the linear independence of the
!       interpolation conditions. The K-th point is a candidate for change
!       if and only if PTSID(K) is nonZERO. In this case let p and q be the
!       integer parts of PTSID(K) and (PTSID(K)-p) multiplied by N+1. If p
!       and q are both positive, the step from XBASE+XOPT to the new K-th
!       interpolation point is PTSAUX(1,p)*e_p + PTSAUX(1,q)*e_q. Otherwise
!       the step is PTSAUX(1,p)*e_p or PTSAUX(2,q)*e_q in the cases q=0 or
!       p=0, respectively.
!     The first NDIM+NPT elements of the array W are used for working space.
!     The final elements of BMAT and ZMAT are set in a well-conditiONEd way
!       to the values that are appropriate for the new interpolation points.
!     The elements of GOPT, HQ and PQ are also revised to the values that are
!       appropriate to the final quadratic model.
!
!     Set some constants.
!
np = n + 1
sfrac = HALF / dfloat(np)
nptm = npt - np
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
almost_infinity = huge(0.0D0) / 2.0D0
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!     Shift the interpolation points so that XOPT becomes the origin, and set
!     the elements of ZMAT to ZERO. The value of SUMPQ is required in the
!     updating of HQ below. The squares of the distances from XOPT to the
!     other interpolation points are set at the end of W. Increments of WINC
!     may be added later to these squares to balance the consideration of
!     the choice of point that is going to become current.
!
sumpq = ZERO
winc = ZERO
do k = 1, npt
    distsq = ZERO
    do j = 1, n
        xpt(k, j) = xpt(k, j) - xopt(j)
        distsq = distsq + xpt(k, j)**2
    end do
    sumpq = sumpq + pq(k)
    w(ndim + k) = distsq
    winc = dmax1(winc, distsq)
    do j = 1, nptm
        zmat(k, j) = ZERO
    end do
end do
!
!     Update HQ so that HQ and PQ define the second derivatives of the model
!     after XBASE has been shifted to the trust region centre.
!
ih = 0
do j = 1, n
    w(j) = HALF * sumpq * xopt(j)
    do k = 1, npt
        w(j) = w(j) + pq(k) * xpt(k, j)
    end do
    do i = 1, j
        ih = ih + 1
        hq(ih) = hq(ih) + w(i) * xopt(j) + w(j) * xopt(i)
    end do
end do
!
!     Shift XBASE, SL, SU and XOPT. Set the elements of BMAT to ZERO, and
!     also set the elements of PTSAUX.
!
do j = 1, n
    xbase(j) = xbase(j) + xopt(j)
    sl(j) = sl(j) - xopt(j)
    su(j) = su(j) - xopt(j)
    xopt(j) = ZERO
    ptsaux(1, j) = dmin1(delta, su(j))
    ptsaux(2, j) = dmax1(-delta, sl(j))
    if (ptsaux(1, j) + ptsaux(2, j) < ZERO) then
        temp = ptsaux(1, j)
        ptsaux(1, j) = ptsaux(2, j)
        ptsaux(2, j) = temp
    end if
    if (dabs(ptsaux(2, j)) < HALF * dabs(ptsaux(1, j))) then
        ptsaux(2, j) = HALF * ptsaux(1, j)
    end if
    do i = 1, ndim
        bmat(i, j) = ZERO
    end do
end do
fbase = fval(kopt)
!
!     Set the identifiers of the artificial interpolation points that are
!     along a coordinate direction from XOPT, and set the corresponding
!     nonZERO elements of BMAT and ZMAT.
!
ptsid(1) = sfrac
do j = 1, n
    jp = j + 1
    jpn = jp + n
    ptsid(jp) = dfloat(j) + sfrac
    if (jpn <= npt) then
        ptsid(jpn) = dfloat(j) / dfloat(np) + sfrac
        temp = ONE / (ptsaux(1, j) - ptsaux(2, j))
        bmat(jp, j) = -temp + ONE / ptsaux(1, j)
        bmat(jpn, j) = temp + ONE / ptsaux(2, j)
        bmat(1, j) = -bmat(jp, j) - bmat(jpn, j)
        zmat(1, j) = dsqrt(2.0D0) / dabs(ptsaux(1, j) * ptsaux(2, j))
        zmat(jp, j) = zmat(1, j) * ptsaux(2, j) * temp
        zmat(jpn, j) = -zmat(1, j) * ptsaux(1, j) * temp
    else
        bmat(1, j) = -ONE / ptsaux(1, j)
        bmat(jp, j) = ONE / ptsaux(1, j)
        bmat(j + npt, j) = -HALF * ptsaux(1, j)**2
    end if
end do
!
!     Set any remaining identifiers with their nonZERO elements of ZMAT.
!
if (npt >= n + np) then
    do k = 2 * np, npt
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!          IW=(DFLOAT(K-NP)-HALF)/DFLOAT(N)
        iw = int((dfloat(k - np) - HALF) / dfloat(n))
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        ip = k - np - iw * n
        iq = ip + iw
        if (iq > n) iq = iq - n
        ptsid(k) = dfloat(ip) + dfloat(iq) / dfloat(np) + sfrac
        temp = ONE / (ptsaux(1, ip) * ptsaux(1, iq))
        zmat(1, k - np) = temp
        zmat(ip + 1, k - np) = -temp
        zmat(iq + 1, k - np) = -temp
        zmat(k, k - np) = temp
    end do
end if
nrem = npt
kold = 1
knew = kopt
!
!     Reorder the provisional points in the way that exchanges PTSID(KOLD)
!     with PTSID(KNEW).
!
80 do j = 1, n
    temp = bmat(kold, j)
    bmat(kold, j) = bmat(knew, j)
    bmat(knew, j) = temp
end do
do j = 1, nptm
    temp = zmat(kold, j)
    zmat(kold, j) = zmat(knew, j)
    zmat(knew, j) = temp
end do
ptsid(kold) = ptsid(knew)
ptsid(knew) = ZERO
w(ndim + knew) = ZERO
nrem = nrem - 1
if (knew /= kopt) then
    temp = vlag(kold)
    vlag(kold) = vlag(knew)
    vlag(knew) = temp
!
!     Update the BMAT and ZMAT matrices so that the status of the KNEW-th
!     interpolation point can be changed from provisional to original. The
!     branch to label 350 occurs if all the original points are reinstated.
!     The nonnegative values of W(NDIM+K) are required in the search below.
!
    call update(n, npt, bmat, zmat, ndim, vlag, beta, denom, knew, w)
    if (nrem == 0) goto 350
    do k = 1, npt
        w(ndim + k) = dabs(w(ndim + k))
    end do
end if
!
!     Pick the index KNEW of an original interpolation point that has not
!     yet replaced ONE of the provisional interpolation points, giving
!     attention to the closeness to XOPT and to previous tries with KNEW.
!
120 dsqmin = ZERO
do k = 1, npt
    if (w(ndim + k) > ZERO) then
        if (dsqmin == ZERO .or. w(ndim + k) < dsqmin) then
            knew = k
            dsqmin = w(ndim + k)
        end if
    end if
end do
if (dsqmin == ZERO) goto 260
!
!     Form the W-vector of the chosen original interpolation point.
!
do j = 1, n
    w(npt + j) = xpt(knew, j)
end do
do k = 1, npt
    sum = ZERO
    if (k == kopt) then
        continue
    else if (ptsid(k) == ZERO) then
        do j = 1, n
            sum = sum + w(npt + j) * xpt(k, j)
        end do
    else
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!          IP=PTSID(K)
        ip = int(ptsid(k))
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        if (ip > 0) sum = w(npt + ip) * ptsaux(1, ip)
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!          IQ=DFLOAT(NP)*PTSID(K)-DFLOAT(IP*NP)
        iq = int(dfloat(np) * ptsid(k) - dfloat(ip * np))
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        if (iq > 0) then
            iw = 1
            if (ip == 0) iw = 2
            sum = sum + w(npt + iq) * ptsaux(iw, iq)
        end if
    end if
    w(k) = HALF * sum * sum
end do
!
!     Calculate VLAG and BETA for the required updating of the H matrix if
!     XPT(KNEW,.) is reinstated in the set of interpolation points.
!
do k = 1, npt
    sum = ZERO
    do j = 1, n
        sum = sum + bmat(k, j) * w(npt + j)
    end do
    vlag(k) = sum
end do
beta = ZERO
do j = 1, nptm
    sum = ZERO
    do k = 1, npt
        sum = sum + zmat(k, j) * w(k)
    end do
    beta = beta - sum * sum
    do k = 1, npt
        vlag(k) = vlag(k) + sum * zmat(k, j)
    end do
end do
bsum = ZERO
distsq = ZERO
do j = 1, n
    sum = ZERO
    do k = 1, npt
        sum = sum + bmat(k, j) * w(k)
    end do
    jp = j + npt
    bsum = bsum + sum * w(jp)
    do ip = npt + 1, ndim
        sum = sum + bmat(ip, j) * w(ip)
    end do
    bsum = bsum + sum * w(jp)
    vlag(jp) = sum
    distsq = distsq + xpt(knew, j)**2
end do
beta = HALF * distsq * distsq + beta - bsum
vlag(kopt) = vlag(kopt) + ONE
!
!     KOLD is set to the index of the provisional interpolation point that is
!     going to be deleted to make way for the KNEW-th original interpolation
!     point. The choice of KOLD is governed by the avoidance of a small value
!     of the denominator in the updating calculation of UPDATE.
!
denom = ZERO
vlmxsq = ZERO
do k = 1, npt
    if (ptsid(k) /= ZERO) then
        hdiag = ZERO
        do j = 1, nptm
            hdiag = hdiag + zmat(k, j)**2
        end do
        den = beta * hdiag + vlag(k)**2
        if (den > denom) then
            kold = k
            denom = den
        end if
    end if
    vlmxsq = dmax1(vlmxsq, vlag(k)**2)
end do
if (denom <= 1.0D-2 * vlmxsq) then
    w(ndim + knew) = -w(ndim + knew) - winc
    goto 120
end if
goto 80
!
!     When label 260 is reached, all the final positions of the interpolation
!     points have been chosen although any changes have not been included yet
!     in XPT. Also the final BMAT and ZMAT matrices are complete, but, apart
!     from the shift of XBASE, the updating of the quadratic model remains to
!     be dONE. The following cycle through the new interpolation points begins
!     by putting the new point in XPT(KPT,.) and by setting PQ(KPT) to ZERO,
!     except that a RETURN occurs if MAXFUN prohibits another value of F.
!
260 do kpt = 1, npt
    if (ptsid(kpt) == ZERO) cycle
    if (nf >= maxfun) then
        nf = -1
        goto 350
    end if
    ih = 0
    do j = 1, n
        w(j) = xpt(kpt, j)
        xpt(kpt, j) = ZERO
        temp = pq(kpt) * w(j)
        do i = 1, j
            ih = ih + 1
            hq(ih) = hq(ih) + temp * w(i)
        end do
    end do
    pq(kpt) = ZERO
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!      IP=PTSID(KPT)
!      IQ=DFLOAT(NP)*PTSID(KPT)-DFLOAT(IP*NP)
    ip = int(ptsid(kpt))
    iq = int(dfloat(np) * ptsid(kpt) - dfloat(ip * np))
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    if (ip > 0) then
        xp = ptsaux(1, ip)
        xpt(kpt, ip) = xp
    end if
    if (iq > 0) then
        xq = ptsaux(1, iq)
        if (ip == 0) xq = ptsaux(2, iq)
        xpt(kpt, iq) = xq
    end if
!
!     Set VQUAD to the value of the current model at the new point.
!
    vquad = fbase
    if (ip > 0) then
        ihp = (ip + ip * ip) / 2
        vquad = vquad + xp * (gopt(ip) + HALF * xp * hq(ihp))
    end if
    if (iq > 0) then
        ihq = (iq + iq * iq) / 2
        vquad = vquad + xq * (gopt(iq) + HALF * xq * hq(ihq))
        if (ip > 0) then
            iw = max(ihp, ihq) - abs(ip - iq)
            vquad = vquad + xp * xq * hq(iw)
        end if
    end if
    do k = 1, npt
        temp = ZERO
        if (ip > 0) temp = temp + xp * xpt(k, ip)
        if (iq > 0) temp = temp + xq * xpt(k, iq)
        vquad = vquad + HALF * pq(k) * temp * temp
    end do
!
!     Calculate F at the new interpolation point, and set DIFF to the factor
!     that is going to multiply the KPT-th Lagrange function when the model
!     is updated to provide interpolation to the new function value.
!
    do i = 1, n
        w(i) = dmin1(dmax1(xl(i), xbase(i) + xpt(kpt, i)), xu(i))
        if (xpt(kpt, i) == sl(i)) w(i) = xl(i)
        if (xpt(kpt, i) == su(i)) w(i) = xu(i)
    end do
    nf = nf + 1

!-------------------------------------------------------------------!
    !call calfun(n, w, f)
    x = w(1:n)
    call evaluate(calfun, x, f)
    call savehist(nf, x, xhist, f, fhist)
!-------------------------------------------------------------------!

    fval(kpt) = f
    if (f < fval(kopt)) kopt = kpt
    diff = f - vquad
!
!     Update the quadratic model. The RETURN from the subroutine occurs when
!     all the new interpolation points are included in the model.
!
    do i = 1, n
        gopt(i) = gopt(i) + diff * bmat(kpt, i)
    end do
    do k = 1, npt
        sum = ZERO
        do j = 1, nptm
            sum = sum + zmat(k, j) * zmat(kpt, j)
        end do
        temp = diff * sum
        if (ptsid(k) == ZERO) then
            pq(k) = pq(k) + temp
        else
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!          IP=PTSID(K)
!          IQ=DFLOAT(NP)*PTSID(K)-DFLOAT(IP*NP)
            ip = int(ptsid(k))
            iq = int(dfloat(np) * ptsid(k) - dfloat(ip * np))
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            ihq = (iq * iq + iq) / 2
            if (ip == 0) then
                hq(ihq) = hq(ihq) + temp * ptsaux(2, iq)**2
            else
                ihp = (ip * ip + ip) / 2
                hq(ihp) = hq(ihp) + temp * ptsaux(1, ip)**2
                if (iq > 0) then
                    hq(ihq) = hq(ihq) + temp * ptsaux(1, iq)**2
                    iw = max(ihp, ihq) - abs(iq - ip)
                    hq(iw) = hq(iw) + temp * ptsaux(1, ip) * ptsaux(1, iq)
                end if
            end if
        end if
    end do
    ptsid(kpt) = ZERO
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!     By Tom (on 03-06-2019):
!     If a NaN or an infinite value has been reached during the
!     evaluation of the objective function, the loop exit after setting
!     all the parameters, not to raise an exception. KOPT is set to KPT
!     to check in BOBYQB weather FVAL(KOPT) is NaN or infinite value or
!     not.
    if (f /= f .or. f > almost_infinity) then
        exit
    end if
!     By Tom (on 04-06-2019):
!     If the target function value is reached, the loop exit and KOPT is
!     set to KPT to check in BOBYQB weather FVAL(KOPT) .LE. FTARGET
    if (f <= ftarget) then
        exit
    end if
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
end do
350 return
end
