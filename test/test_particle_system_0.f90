! This file is part of RMPCDMD
! Copyright (c) 2015-2016 Pierre de Buyl and contributors
! License: BSD 3-clause (see file LICENSE)

program test_particle_system_0
  use particle_system
  use mt19937ar_module
  use threefry_module
  use iso_c_binding
  use tester
  implicit none

  type(particle_system_t) :: p
  integer, parameter :: N = 3000
  type(mt19937ar_t), target :: mt
  type(tester_t) :: test

  type(threefry_rng_t) :: state(1)
  integer :: clock, i
  double precision :: L(3), x(3)

  call system_clock(count=clock)
  call init_genrand(mt, int(clock, c_long))
  write(*,*) clock
  call test% init(tolerance64=12*epsilon(1.d0))

  call threefry_rng_init(state, int(clock, c_int64_t))

  call p% init(N)
  L = [ 1.d0, 20.d0, 5.d0 ]
  call p% random_placement(L, state=state(1))
  p% pos_old = p% pos

  ! Pick particle i and a random vector of norm <= sqrt(3)
  i = modulo(int(genrand_int31(mt)), N) + 1
  x = [ genrand_real1(mt), genrand_real1(mt), genrand_real1(mt) ]
  write(*,*) 'i', i
  write(*,*) 'x', x
  write(*,*) 'pos(:,i)', p% pos(:,i)
  p% pos(:,i) = p% pos(:,i) + x
  write(*,*) 'pos(:,i)', p% pos(:,i)
  call test% assert_positive( sqrt(3.d0) - p% maximum_displacement() )

  ! Restore particle i
  p% pos(:,i) = p% pos(:,i) - x
  write(*,*) 'pos(:,i)', p% pos(:,i)
  call test% assert_close( p% maximum_displacement(), 0.d0 )

  call test% print()

end program test_particle_system_0
