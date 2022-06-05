module initialize_mod
!--------------------------------------------------------------------------------------------------!
! This module performs the initialization of BOBYQA.
!
! Coded by Zaikun ZHANG (www.zhangzk.net) based on Powell's code and the BOBYQA paper.
!
! Dedicated to late Professor M. J. D. Powell FRS (1936--2015).
!
! Started: February 2022
!
! Last Modified: Sunday, June 05, 2022 AM08:33:22
!--------------------------------------------------------------------------------------------------!

implicit none
private
public :: initialize


contains


subroutine initialize(calfun, iprint, ftarget, rhobeg, sl, su, x0, xl, xu, &
    & kopt, nf, bmat, f, fhist, fval, gopt, hq, pq, xbase, xhist, xpt, zmat)

use, non_intrinsic :: consts_mod, only : RP, IK, ZERO, ONE, TWO, HALF, HUGENUM, DEBUGGING
use, non_intrinsic :: debug_mod, only : assert
use, non_intrinsic :: evaluate_mod, only : evaluate
use, non_intrinsic :: history_mod, only : savehist
use, non_intrinsic :: infnan_mod, only : is_nan, is_posinf, is_finite
use, non_intrinsic :: linalg_mod, only : matprod, trueloc, issymmetric!, norm
use, non_intrinsic :: pintrf_mod, only : OBJ

implicit none

! Inputs
procedure(OBJ) :: calfun  ! N.B.: INTENT cannot be specified if a dummy procedure is not a POINTER
integer(IK), intent(in) :: iprint
real(RP), intent(in) :: ftarget
real(RP), intent(in) :: rhobeg
real(RP), intent(in) :: sl(:)  ! SL(N)
real(RP), intent(in) :: su(:)  ! SU(N)
real(RP), intent(in) :: x0(:)  ! X(N)
real(RP), intent(in) :: xl(:)  ! XL(N)
real(RP), intent(in) :: xu(:)  ! XU(N)

! Outputs
integer(IK), intent(out) :: kopt
integer(IK), intent(out) :: nf
real(RP), intent(out) :: bmat(:, :)  ! BMAT(N, NPT + N)
real(RP), intent(out) :: f
real(RP), intent(out) :: fhist(:)
real(RP), intent(out) :: fval(:)  ! FVAL(NPT)
real(RP), intent(out) :: gopt(:)  ! GOPT(N)
real(RP), intent(out) :: hq(:, :)  ! HQ(N, N)
real(RP), intent(out) :: pq(:)  ! PQ(NPT)
real(RP), intent(out) :: xbase(:)  ! XBASE(N)
real(RP), intent(out) :: xhist(:, :)  ! XHIST(N, MAXXHIST)
real(RP), intent(out) :: xpt(:, :)  ! XPT(N, NPT)
real(RP), intent(out) :: zmat(:, :)  ! ZMAT(NPT, NPT-N-1)

! Local variables
character(len=*), parameter :: srname = 'INITIIALIZE'
integer(IK) :: maxfhist
integer(IK) :: maxhist
integer(IK) :: maxxhist
integer(IK) :: n
integer(IK) :: npt
real(RP) :: x(size(x0))
real(RP) :: diff, fbeg, recip, rhosq, stepa, stepb, temp
integer(IK) :: ipt, itemp, jpt
logical :: evaluated(size(fval))

! Sizes.
n = int(size(x0), kind(n))
npt = int(size(fval), kind(npt))
maxxhist = int(size(xhist, 2), kind(maxxhist))
maxfhist = int(size(fhist), kind(maxfhist))
maxhist = int(max(maxxhist, maxfhist), kind(maxhist))

! Preconditions
if (DEBUGGING) then
    call assert(abs(iprint) <= 3, 'IPRINT is 0, 1, -1, 2, -2, 3, or -3', srname)
    call assert(n >= 1, 'N >= 1', srname)
    call assert(npt >= n + 2, 'NPT >= N+2', srname)
    call assert(rhobeg > 0, 'RHOBEG > 0', srname)
    call assert(size(sl) == n .and. all(sl <= 0), 'SIZE(SL) == N, SL <= 0', srname)
    call assert(size(su) == n .and. all(su >= 0), 'SIZE(SU) == N, SU >= 0', srname)
    call assert(size(xl) == n .and. size(xu) == n, 'SIZE(XL) == N == SIZE(XU)', srname)
    call assert(all(is_finite(x0) .and. x0 >= xl .and. x0 <= xu), 'X0 is finite, XL <= X0 <= XU', srname)
    call assert(size(bmat, 1) == n .and. size(bmat, 2) == npt + n, 'SIZE(BMAT) == [N, NPT+N]', srname)
    call assert(size(zmat, 1) == npt .and. size(zmat, 2) == npt - n - 1_IK, 'SIZE(ZMAT) == [NPT, NPT-N-1]', srname)
    call assert(size(gopt) == n, 'SIZE(GOPT) == N', srname)
    call assert(size(hq, 1) == n .and. size(hq, 2) == n, 'SIZE(HQ) == [N, N]', srname)
    call assert(size(pq) == npt, 'SIZE(PQ) == NPT', srname)
    call assert(size(xbase) == n, 'SIZE(XBASE) == N', srname)
    call assert(size(xpt, 1) == n .and. size(xpt, 2) == npt, 'SIZE(XPT) == [N, NPT]', srname)
    call assert(size(xhist, 1) == n .and. maxxhist * (maxxhist - maxhist) == 0, &
        & 'SIZE(XHIST, 1) == N, SIZE(XHIST, 2) == 0 or MAXHIST', srname)
    call assert(maxfhist * (maxfhist - maxhist) == 0, 'SIZE(FHIST) == 0 or MAXHIST', srname)
end if

!--------------------------------------------------------------------------------------------------!
ipt = 1; jpt = 1  ! Temporary fix for G95 warning about these variables used uninitialized
!--------------------------------------------------------------------------------------------------!
!
!     The arguments N, NPT, X, XL, XU, RHOBEG, IPRINT and MAXFUN are the
!       same as the corresponding arguments in SUBROUTINE BOBYQA.
!     The arguments XBASE, XPT, FVAL, HQ, PQ, BMAT, ZMAT, NDIM, SL and SU
!       are the same as the corresponding arguments in BOBYQB, the elements
!       of SL and SU being set in BOBYQA.
!     GOPT is usually the gradient of the quadratic model at XOPT+XBASE, but
!       it is set by PRELIM to the gradient of the quadratic model at XBASE.
!       If XOPT is nonzero, BOBYQB will change it to its usual value later.
!     NF is maintaned as the number of calls of CALFUN so far.
!     KOPT will be such that the least calculated value of F so far is at
!       the point XPT(KOPT,.)+XBASE in the space of the variables.
!
!     SUBROUTINE PRELIM sets the elements of XBASE, XPT, FVAL, GOPT, HQ, PQ,
!     BMAT and ZMAT for the first iteration, and it maintains the values of
!     NF and KOPT. The vector X is also changed by PRELIM.
!
!     Set some constants.
!
! EVALUATED is a boolean array with EVALUATED(I) indicating whether the function value of the I-th
! interpolation point has been evaluated. We need it for a portable counting of the number of
! function evaluations, especially if the loop is conducted asynchronously.
evaluated = .false.
! Initialize FVAL to HUGENUM. Otherwise, compilers may complain that FVAL is not (completely)
! initialized if the initialization aborts due to abnormality (see CHECKEXIT).
fval = HUGENUM
rhosq = rhobeg * rhobeg
recip = ONE / rhosq

! Set XBASE to the initial vector of variables, and set the initial elements of XPT, BMAT, HQ, PQ
! and ZMAT to ZERO.
xbase = x0
xpt = ZERO
hq = ZERO
pq = ZERO
bmat = ZERO
zmat = ZERO

! Begin the initialization procedure. NF becomes one more than the number of function values so far.
! The coordinates of the displacement of the next initial interpolation point from XBASE are set in
! XPT(NF+1,.).
do nf = 1, npt
    if (nf <= 2 * n + 1) then
        if (nf >= 2 .and. nf <= n + 1) then
            xpt(nf - 1, nf) = rhobeg
            if (su(nf - 1) <= 0) then  ! SU(NF - 1) == 0
                xpt(nf - 1, nf) = -rhobeg
            end if
        else if (nf >= n + 2) then
            xpt(nf - n - 1, nf) = -rhobeg
            if (sl(nf - n - 1) >= 0) then  ! SL(NF - N - 1) == 0
                xpt(nf - n - 1, nf) = min(TWO * rhobeg, su(nf - n - 1))
            end if
            if (su(nf - n - 1) <= 0) then  ! SU(NF - N - 1) == 0
                xpt(nf - n - 1, nf) = max(-TWO * rhobeg, sl(nf - n - 1))
            end if
        end if
    else
        itemp = (nf - n - 2) / n
        jpt = nf - (itemp + 1) * n - 1
        ipt = jpt + itemp
        if (ipt > n) then
            itemp = jpt
            jpt = ipt - n
            ipt = itemp
        end if
        xpt(ipt, nf) = xpt(ipt, ipt + 1)
        xpt(jpt, nf) = xpt(jpt, jpt + 1)
    end if

    ! Calculate the next value of F. The least function value so far and its index are required.
    x = min(max(xl, xbase + xpt(:, nf)), xu)
    x(trueloc(xpt(:, nf) <= sl)) = xl(trueloc(xpt(:, nf) <= sl))
    x(trueloc(xpt(:, nf) >= su)) = xu(trueloc(xpt(:, nf) >= su))

    call evaluate(calfun, x, f)
    call savehist(nf, x, xhist, f, fhist)
    evaluated(nf) = .true.
    fval(nf) = f
    if (nf == 1) then
        fbeg = f
    end if


! Set the nonzero initial elements of BMAT and the quadratic model in the cases when NF is at most
! 2*N+1. If NF exceeds N+1, then the positions of the NF-th and (NF-N)-th interpolation points may
! be switched, in order that the function value at the first of them contributes to the off-diagonal
! second derivative terms of the initial quadratic model.
!do nf = 1, npt
!    f = fval(nf)
    if (nf <= 2 * n + 1) then
        if (nf >= 2 .and. nf <= n + 1) then
            gopt(nf - 1) = (f - fbeg) / xpt(nf - 1, nf)
            if (npt < nf + n) then
                bmat(nf - 1, 1) = -ONE / xpt(nf - 1, nf)
                bmat(nf - 1, nf) = ONE / xpt(nf - 1, nf)
                bmat(nf - 1, npt + nf - 1) = -HALF * rhosq
            end if
        else if (nf >= n + 2) then
            stepa = xpt(nf - n - 1, nf - n)
            stepb = xpt(nf - n - 1, nf)
            temp = (f - fbeg) / stepb
            diff = stepb - stepa
            hq(nf - n - 1, nf - n - 1) = TWO * (temp - gopt(nf - n - 1)) / diff
            gopt(nf - n - 1) = (gopt(nf - n - 1) * stepb - temp * stepa) / diff
            if (stepa * stepb < ZERO .and. fval(nf) < fval(nf - n)) then
                ! Switch the NF-th and (NF-N)-th interpolation points.
                fval([nf, nf - n]) = fval([nf - n, nf])
                xpt(nf - n - 1, [nf - n, nf]) = xpt(nf - n - 1, [nf, nf - n])
            end if
            bmat(nf - n - 1, 1) = -(stepa + stepb) / (stepa * stepb)
            bmat(nf - n - 1, nf) = -HALF / xpt(nf - n - 1, nf - n)
            bmat(nf - n - 1, nf - n) = -bmat(nf - n - 1, 1) - bmat(nf - n - 1, nf)
            zmat(1, nf - n - 1) = sqrt(TWO) / (stepa * stepb)
            zmat(nf, nf - n - 1) = sqrt(HALF) / rhosq
            zmat(nf - n, nf - n - 1) = -zmat(1, nf - n - 1) - zmat(nf, nf - n - 1)
        end if
! Set the off-diagonal second derivatives of the Lagrange functions and the initial quadratic model.
    else
        zmat(1, nf - n - 1) = recip
        zmat(nf, nf - n - 1) = recip
        zmat(ipt + 1, nf - n - 1) = -recip
        zmat(jpt + 1, nf - n - 1) = -recip
        temp = xpt(ipt, nf) * xpt(jpt, nf)
        hq(ipt, jpt) = (fbeg - fval(ipt + 1) - fval(jpt + 1) + f) / temp
        hq(jpt, ipt) = hq(ipt, jpt)
    end if
    if (f <= ftarget .or. is_nan(f) .or. is_posinf(f)) exit
    !if (nf >= npt) exit
end do

!nf = min(nf, npt)  ! NF may be NPT+1 at exit of the loop.
nf = count(evaluated)
kopt = int(minloc(fval, mask=evaluated, dim=1), kind(kopt))
if (kopt /= 1 .and. all(evaluated)) then
    gopt = gopt + matprod(hq, xpt(:, kopt))
end if


! Postconditions
if (DEBUGGING) then
    call assert(nf <= npt, 'NF <= NPT', srname)
    call assert(kopt >= 1 .and. kopt <= npt, '1 <= KOPT <= NPT', srname)
    call assert(size(xbase) == n .and. all(is_finite(xbase)), 'SIZE(XBASE) == N, XBASE is finite', srname)
    call assert(all(xbase >= xl .and. xbase <= xu), 'XL <= XBASE <= XU', srname)
    call assert(size(xpt, 1) == n .and. size(xpt, 2) == npt, 'SIZE(XPT) == [N, NPT]', srname)
    call assert(all(is_finite(xpt)), 'XPT is finite', srname)
    call assert(all(xpt >= spread(sl, dim=2, ncopies=npt)) .and. &
        & all(xpt <= spread(su, dim=2, ncopies=npt)), 'SL <= XPT <= SU', srname)
    call assert(size(fval) == npt .and. .not. any(evaluated .and. (is_nan(fval) .or. is_posinf(fval))), &
        & 'SIZE(FVAL) == NPT and FVAL is not NaN or +Inf', srname)
    call assert(.not. any(fval < fval(kopt) .and. evaluated), 'FVAL(KOPT) = MINVAL(FVAL)', srname)
    call assert(size(fhist) == maxfhist, 'SIZE(FHIST) == MAXFHIST', srname)
    call assert(size(bmat, 1) == n .and. size(bmat, 2) == npt + n, 'SIZE(BMAT) == [N, NPT+N]', srname)
    call assert(issymmetric(bmat(:, npt + 1:npt + n)), 'BMAT(:, NPT+1:NPT+N) is symmetric', srname)
    call assert(size(zmat, 1) == npt .and. size(zmat, 2) == npt - n - 1_IK, 'SIZE(ZMAT) == [NPT, NPT-N-1]', srname)
end if

end subroutine initialize


end module initialize_mod
