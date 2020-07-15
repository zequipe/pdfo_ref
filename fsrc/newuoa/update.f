      module update_mod

      implicit none
      private
      public :: updateh, updateq, qalt


      contains

      subroutine updateh(bmat, zmat, idz, vlag, beta, knew)
      ! UPDATE updates arrays BMAT and ZMAT together with IDZ, in order
      ! to shift the interpolation point that has index KNEW. On entry, 
      ! VLAG contains the components of the vector THETA*WCHECK + e_b 
      ! of the updating formula (6.11) in the NEWUOA paper, and BETA
      ! holds the value of the parameter that has this name. 
      
      ! Although VLAG will be modified below, its value will NOT be used 
      ! by other parts of NEWUOA after returning from UPDATE. Its value 
      ! will be overwritten when trying the alternative model or by
      ! VLAGBETA.

      use consts_mod, only : RP, IK, ONE, ZERO, DEBUG_MODE, SRNLEN
      use warnerror_mod, only : errstop
      use lina_mod
      implicit none

      integer(IK), intent(in) :: knew
      integer(IK), intent(inout) :: idz
      real(RP), intent(in) :: beta
      real(RP), intent(inout) :: bmat(:, :)  ! BMAT(N, NPT + N)
      real(RP), intent(inout) :: zmat(:, :)  ! ZMAT(NPT, NPT - N - 1)
      real(RP), intent(inout) :: vlag(:)     ! VLAG(NPT + N)

      integer(IK) :: iflag, j, ja, jb, jl, n, npt
      real(RP) :: c, s, r, alpha, denom, scala, scalb, tau, tausq, temp,&
     & tempa, tempb, ztemp(size(zmat, 1)), w(size(vlag)),               &
     & v1(size(bmat, 1)), v2(size(bmat, 1))
      character(len = SRNLEN), parameter :: srname = 'UPDATEH'

      
      ! Get and verify the sizes.
      n = size(bmat, 1)
      npt = size(bmat, 2) - n

      if (DEBUG_MODE) then
          if (n == 0 .or. npt < n + 2) then
              call errstop(srname, 'SIZE(BMAT) is invalid')
          end if
          if (size(zmat, 1) /= npt .or. size(zmat, 2) /= npt-n-1) then
              call errstop(srname, 'SIZE(ZMAT) is invalid')
          end if
          if (size(vlag) /= npt + n) then
              call errstop(srname, 'SIZE(VLAG) is invalid')
          end if
      end if
      
          
      ! Apply the rotations that put zeros in the KNEW-th row of ZMAT.
      ! A Givens rotation will be multiplied to ZMAT from the left so
      ! ZMAT(KNEW, JL) becomes SQRT(ZMAT(KNEW, JL)^2+ZMAT(KNEW,J)) and
      ! ZMAT(KNEW, J) becomes 0. 
      jl = 1  ! For J = 2, ..., IDZ - 1, set JL = 1.
      do j = 2, idz - 1
          if (abs(zmat(knew, j)) >  ZERO) then
              !call givens(zmat(knew, jl), zmat(knew, j), c, s, r)
              c = zmat(knew, jl)
              s = zmat(knew, j)
              r = hypot(c, s) 
              c = c/r
              s = s/r
              ztemp = zmat(:, j)
              zmat(:, j) = c*ztemp - s*zmat(:, jl)
              zmat(:, jl) = c*zmat(:, jl) + s*ztemp
              zmat(knew, j) = ZERO
      !----------------------------------------------------------------!
              !!! In later vesions, we will include the following line.
              !!! For the moment, we exclude it to align with Powell's 
              !!! version.
              !!! Preliminary tests show that including this line can
              !!! improve the performance.
!-------------!zmat(knew, jl) = r  !-----------------------------------! 
      !----------------------------------------------------------------!
          end if
      end do

      if (idz <= npt - n - 1) then
          jl = idz  ! For J = IDZ + 1, ..., NPT - N - 1, set JL = IDZ.
      end if
      do j = idz + 1, npt - n - 1
          if (abs(zmat(knew, j)) >  ZERO) then
              !call givens(zmat(knew, jl), zmat(knew, j), c, s, r)
              c = zmat(knew, jl)
              s = zmat(knew, j)
              r = hypot(c, s) 
              c = c/r
              s = s/r
              ztemp = zmat(:, j)
              zmat(:, j) = c*ztemp - s*zmat(:, jl)
              zmat(:, jl) = c*zmat(:, jl) + s*ztemp
              zmat(knew, j) = ZERO
      !----------------------------------------------------------------!
              !!! In later vesions, we will include the following line.
              !!! For the moment, we exclude it to align with Powell's 
              !!! version.
              !!! Preliminary tests show that including this line can
              !!! improve the performance.
!-------------!zmat(knew, jl) = r  !-----------------------------------! 
      !----------------------------------------------------------------!
          end if
      end do
      
      ! JL plays an important role below. There are two possibilities:
      ! JL = 1 < IDZ iff IDZ = 1 
      ! JL = IDZ > 1 iff 2 <= IDZ <= NPT - N - 1

      ! Put the first NPT components of the KNEW-th column of HLAG into 
      ! W, and calculate the parameters of the updating formula.
      tempa = zmat(knew, 1)
      if (idz >=  2) then
          tempa = -tempa
      end if

      w(1 : npt) = tempa*zmat(:, 1)
      if (jl > 1) then
          tempb = zmat(knew, jl)
          w(1 : npt) = w(1 : npt) + tempb*zmat(:, jl)
      end if

      alpha = w(knew)
      tau = vlag(knew)
      tausq = tau*tau
      denom = alpha*beta + tausq
      vlag(knew) = vlag(knew) - ONE
      
      ! Complete the updating of ZMAT when there is only one nonzero
      ! element in the KNEW-th row of the new matrix ZMAT, but, if
      ! IFLAG is set to one, then the first column of ZMAT will be 
      ! exchanged with another one later.
      iflag = 0
      if (jl == 1) then
          ! There is only one nonzero in ZMAT(KNEW, :) after the
          ! rotation. This is the normal case, because IDZ is 1 in
          ! precise arithmetic. 
          temp = sqrt(abs(denom))
          tempb = tempa/temp
          tempa = tau/temp
          zmat(:, 1) = tempa*zmat(:, 1) - tempb*vlag(1 : npt)
      !----------------------------------------------------------------!
          if (idz == 1 .and. temp < ZERO) then
!---------!if (idz == 1 .and. denom < ZERO) then !---------------------!
      !----------------------------------------------------------------!
              ! TEMP < ZERO?!! Powell wrote this but it is STRANGE!!!!!!
              !!! It is probably a BUG !!!
              ! According to (4.18) of the NEWUOA paper, the 
              ! "TEMP < ZERO" here and "TEMP >= ZERO" below should be
              ! revised by replacing "TEMP" with DENOM, which is denoted
              ! by sigma in the paper. See also the corresponding part
              ! of the LINCOA code (which has also some strangeness).
              ! It seems that the BOBYQA code does not have this part
              ! --- it does not have IDZ at all (why?).
              idz = 2
          end if
      !----------------------------------------------------------------!
          if (idz >= 2 .and. temp >= ZERO) then 
!---------!if (idz >= 2 .and. denom >= ZERO) then !--------------------!
      !----------------------------------------------------------------!
              ! JL = 1 and IDZ >= 2??? Seems not possible either!!!
              iflag = 1
          end if
      else
          ! Complete the updating of ZMAT in the alternative case.
          ! There are two nonzeros in ZMAT(KNEW, :) after the rotation.
          ja = 1
          if (beta >=  ZERO) then 
              ja = jl
          end if
          jb = jl + 1 - ja
          temp = zmat(knew, jb)/denom
          tempa = temp*beta
          tempb = temp*tau
          temp = zmat(knew, ja)
          scala = ONE/sqrt(abs(beta)*temp*temp + tausq)
          scalb = scala*sqrt(abs(denom))
          zmat(:, ja) = scala*(tau*zmat(:, ja) - temp*vlag(1 : npt))
          zmat(:, jb) = scalb*(zmat(:, jb) - tempa*w(1 : npt) -         &
     &     tempb*vlag(1 : npt))
          
          if (denom <=  ZERO) then
              if (beta < ZERO) then 
                  idz = idz + 1  ! Is it possible to get IDZ > NPT-N-1?
              end if
              if (beta >=  ZERO) then 
                  iflag = 1
              end if
          end if
      end if
      
      ! IDZ is reduced in the following case,  and usually the first
      ! column of ZMAT is exchanged with a later one.
      if (iflag == 1) then
          idz = idz - 1
          if (idz > 1) then
              ztemp = zmat(:, 1)
              zmat(:, 1) = zmat(:, idz)
              zmat(:, idz) = ztemp
          end if
      end if
      
      ! Finally,  update the matrix BMAT.
      w(npt + 1 : npt + n) = bmat(:, knew)
      v1 = (alpha*vlag(npt+1 : npt+n) - tau*w(npt+1 : npt+n))/denom
      v2 = (-beta*w(npt+1 : npt+n) - tau*vlag(npt+1 : npt+n))/denom

!      !-------------------POWELL'S IMPLEMENTATION----------------------!
!      do j = 1, n
!          bmat(j, 1 : npt + j) = bmat(j, 1 : npt + j) +                 &
!     &     v1(j)*vlag(1 : npt + j) + v2(j)*w(1 : npt + j)
!      ! Set the upper triangular part of BMAT(:,NPT+1:NPT+N) by symmetry
!      ! Note that SHIFTBASE sets the lower triangular part by copying
!      ! the upper triangular part, but here it does the opposite. There 
!      ! seems not any particular reason to keep them different. It was
!      ! probably an ad-hoc decision that Powell made when coding. 
!          bmat(1 : j - 1, npt + j) = bmat(j, npt + 1 : npt + j - 1)
!      end do 
!      !---------------POWELL'S IMPLEMENTATION ENDS---------------------!

      !-----------------MATRIX-VECTOR IMPLEMENTATION-------------------!
      call r2update(bmat, ONE, v1, vlag, ONE, v2, w)
      ! In floating-point arithmetic, the update above does not guarante
      ! BMAT(:, NPT+1 : NPT+N) to be symmetric. Symmetrization needed.
      call symmetrize(bmat(:, npt + 1 : npt + n))
      !----------------------------------------------------------------!

      return

      end subroutine updateh


      subroutine updateq(idz, knew, fqdiff, xptknew, bmatknew, zmat, gq,&
     & hq, pq)

      use warnerror_mod, only : errstop
      use consts_mod, only : RP, IK, ZERO, DEBUG_MODE, SRNLEN
      use lina_mod
      implicit none

      integer(IK), intent(in) :: idz
      integer(IK), intent(in) :: knew
      real(RP), intent(in) :: fqdiff
      real(RP), intent(in) :: xptknew(:)  ! XPTKNEW(N)
      real(RP), intent(in) :: bmatknew(:) ! BMATKNEW(N)
      real(RP), intent(in) :: zmat(:, :)  ! ZMAT(NPT, NPT - N - 1)
      real(RP), intent(inout) :: gq(:)   ! GQ(N)
      real(RP), intent(inout) :: hq(:, :)! HQ(N, N)
      real(RP), intent(inout) :: pq(:)   ! PQ(NPT) 

      integer(IK) :: j, n, npt
      real(RP) :: fqdz(size(zmat, 2))
      character(len = SRNLEN), parameter :: srname = 'UPDATEQ'

      
      ! Get and verify the sizes.
      n = size(gq)
      npt = size(pq)

      if (DEBUG_MODE) then
          if (n == 0 .or. npt < n + 2) then
              call errstop(srname, 'SIZE(GQ) or SIZE(PQ) is invalid')
          end if
          if (size(zmat, 1) /= npt .or. size(zmat, 2) /= npt-n-1) then
              call errstop(srname, 'SIZE(ZMAT) is invalid')
          end if
          if (size(xptknew) /= n) then
              call errstop(srname, 'SIZE(XPTKNEW) is invalid')
          end if
          if (size(bmatknew) /= n) then
              call errstop(srname, 'SIZE(BMATKNEW) is invalid')
          end if
          if (size(hq, 1) /= n .or. size(hq, 2) /= n) then
              call errstop(srname, 'SIZE(HQ) is invalid')
          end if
      end if

      !----------------------------------------------------------------!
      ! Implement R1UPDATE properly so that it ensures HQ is symmetric.
      call r1update(hq, pq(knew), xptknew)
      !----------------------------------------------------------------!

      ! Update the implicit part of second derivatives.
      fqdz = fqdiff*zmat(knew, :)
      fqdz(1 : idz - 1) = -fqdz(1 : idz - 1)
      pq(knew) = ZERO
      !----------------------------------------------------------------!
      !!! The following DO LOOP implements the update given below, yet
      !!! the result will not be exactly the same due to the
      !!! non-associativity of floating point arithmetic addition.
      !!! In future versions, we will use MATMUL instead of DO LOOP.
!----!pq = pq + matmul(zmat, fqdz) !-----------------------------------!
      !----------------------------------------------------------------!
      do j = 1, npt - n - 1
          pq = pq + fqdz(j)*zmat(:, j)
      end do

      ! Update the gradient.
      gq = gq + fqdiff*bmatknew

      return 

      end subroutine updateq


      subroutine qalt(gq, hq, pq, fval, smat, zmat, kopt, idz)
      ! QALT calculates the alternative model, namely the model that
      ! minimizes the F-norm of the Hessian subject to the interpolation
      ! conditions. 
      ! Note that SMAT = BMAT(:, 1:NPT)

      use consts_mod, only : RP, IK, ZERO, DEBUG_MODE, SRNLEN
      use warnerror_mod
      use lina_mod
      implicit none

      integer(IK), intent(in) :: kopt
      integer(IK), intent(in) :: idz
      real(RP), intent(in) :: fval(:)       ! FVAL(NPT)
      real(RP), intent(in) :: smat(:, :)    ! SMAT(N, NPT)
      real(RP), intent(in) :: zmat(:, :)    ! ZMAT(NPT, NPT-N-!)
      real(RP), intent(out) :: gq(:)        ! GQ(N)
      real(RP), intent(out) :: hq(:, :)     ! HQ(N, N)
      real(RP), intent(out) :: pq(:)        ! PQ(NPT)

      real(RP) :: vlag(size(pq)), vz(size(zmat, 2))
      integer(IK) :: n, npt
      character(len = SRNLEN), parameter :: srname = 'QALT'


      ! Get and verify the sizes.
      n = size(gq)
      npt = size(pq)

      if (DEBUG_MODE) then
          if (n == 0 .or. npt < n + 2) then
              call errstop(srname, 'SIZE(GQ) or SIZE(PQ) is invalid')
          end if
          if (size(fval) /= npt) then
              call errstop(srname, 'SIZE(FVAL) /= NPT')
          end if
          if (size(smat, 1) /= n .or. size(smat, 2) /= npt) then
              call errstop(srname, 'SIZE(SMAT) is invalid')
          end if
          if (size(zmat, 1) /= npt .or. size(zmat, 2) /= npt-n-1) then
              call errstop(srname, 'SIZE(ZMAT) is invalid')
          end if
          if (size(hq, 1) /= n .or. size(hq, 2) /= n) then
              call errstop(srname, 'SIZE(HQ) is invalid')
          end if
      end if

      vlag = fval - fval(kopt)
      gq = matmul(smat, vlag)
      hq = ZERO
      vz = matmul(vlag, zmat)
      vz(1 : idz - 1) = - vz(1 : idz - 1)
      pq = matmul(zmat, vz)

      return

      end subroutine qalt

      end module update_mod
