!        This is file : test
! Author= zaikunzhang
! Started at: 10.11.2021
! Last Modified: Wednesday, November 10, 2021 PM08:54:46

program test
use linalg_mod
use rand_mod
implicit none

integer, parameter :: n = 5000
real(kind(0.0D0)) :: A(n, n)

A = rand(n, n)

write (*, *) maxval(abs(matprod(A, inv(A)) - eye(n)))

end program test
