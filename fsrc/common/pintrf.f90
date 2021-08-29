! PINTRF_MOD is a module specifying the abstract interfaces FUNEVAL and
! FCEVAL. FUNEVAL evaluates the objective function for unconstrained,
! bound constrained, and linearly constrained problems; FCEVAL evaluates
! the objective function and constraint for nonlinearly constrained prolems.
!
! Coded by Zaikun Zhang in July 2020.
!
! Last Modified: Sunday, May 23, 2021 AM11:08:43
!
!!!!!! Users must provide the implementation of FUNEVAL or FCEVAL. !!!!!!


module pintrf_mod

implicit none
private
public :: FUNEVAL, FCEVAL

abstract interface
    subroutine FUNEVAL(x, f)
    use consts_mod, only : RP
    implicit none
    real(RP), intent(in) :: x(:)
    real(RP), intent(out) :: f
    end subroutine FUNEVAL
end interface


abstract interface
    subroutine FCEVAL(x, f, constr)
    use consts_mod, only : RP
    implicit none
    real(RP), intent(in) :: x(:)
    real(RP), intent(out) :: f
    real(RP), intent(out) :: constr(:)
    end subroutine FCEVAL
end interface

end module pintrf_mod
