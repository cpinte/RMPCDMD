! This file is part of RMPCDMD
! Copyright (c) 2015-2017 Pierre de Buyl and contributors
! License: BSD 3-clause (see file LICENSE)

!> Spatial cells
!!
!! This module defines a derived type cell_system_t that contains the information for a
!! 3-dimensional cartesian cell and the associated compact Hilbert index (see module
!! hilbert).

module cell_system
  use hilbert
  implicit none

  private

  public :: cell_system_t
  public :: PERIODIC_BC, BOUNCE_BACK_BC, SPECULAR_BC

  type cell_system_t
     integer :: L(3)
     double precision :: edges(3)
     integer :: N
     double precision :: a
     double precision :: origin(3)
     integer, allocatable :: cell_count(:)
     integer, allocatable :: cell_count_tmp(:,:)
     integer, allocatable :: cell_start(:)
     logical, allocatable :: is_md(:)
     logical, allocatable :: is_reac(:)
     double precision :: max_v
     integer :: M(3)
     integer :: bc(3)
     logical :: has_walls
   contains
     procedure :: init
     procedure :: count_particles
     procedure :: sort_particles
     procedure :: random_shift
     procedure :: cartesian_indices
  end type cell_system_t

  integer, parameter :: PERIODIC_BC = 1
  integer, parameter :: BOUNCE_BACK_BC = 2
  integer, parameter :: SPECULAR_BC = 3

contains

  subroutine init(this, L, a, has_walls)
    use omp_lib
    class(cell_system_t), intent(out) :: this
    integer, intent(in) :: L(3)
    double precision, intent(in) :: a
    logical, intent(in), optional :: has_walls

    integer :: i

    this%L = L
    this% edges = L*a
    if (present(has_walls)) then
       this% has_walls = has_walls
    else
       this% has_walls = .false.
    end if
    if (this% has_walls) then
       this%L(3) = L(3) + 1
    end if
    this%a = a
    this%M = 1
    this%origin = 0.d0

    do i=1, 3
       do while ( 2**this%M(i) < L(i) )
          this%M(i) = this%M(i)+1
       end do
    end do
    this%N = 2**this%M(1)*2**this%M(2)*2**this%M(3)
    allocate(this%cell_count(this%N))
    allocate(this%cell_count_tmp(this%N, omp_get_max_threads()))
    allocate(this%cell_start(this%N))
    allocate(this%is_md(this%N))
    allocate(this%is_reac(this%N))

  end subroutine init

  subroutine count_particles(this, position)
    use omp_lib
    class(cell_system_t), intent(inout) :: this
    double precision, intent(in) :: position(:, :)

    integer :: i, idx, N_particles, thread_max
    integer :: p(3)
    integer :: L(3)
    logical :: nowalls
    integer :: thread_id

    N_particles = size(position, 2)
    thread_max = omp_get_max_threads()

    L = this% L
    nowalls = .not. this% has_walls

    this%cell_count_tmp = 0

    !$omp parallel private(thread_id)
    thread_id = omp_get_thread_num() + 1
    !$omp do private(i, p, idx)
    do i=1, N_particles
       p = this%cartesian_indices(position(:,i))
       idx = compact_p_to_h(p, this%M) + 1
       this%cell_count_tmp(idx, thread_id) = this%cell_count_tmp(idx, thread_id) + 1
    end do
    !$omp end do
    !$omp end parallel

    !$omp parallel do private(thread_id)
    do i = 1, this%N
       this%cell_count(i) = 0
       do thread_id=1, thread_max
          this%cell_count(i) = this%cell_count(i) + this%cell_count_tmp(i, thread_id)
       end do
    end do

    this%cell_start(1) = 1
    do i=2, this%N
       this%cell_start(i) = this%cell_start(i-1) + this%cell_count(i-1)
    end do

  end subroutine count_particles

  subroutine sort_particles(this, position_old, position_new)
    class(cell_system_t), intent(inout) :: this
    double precision, intent(in) :: position_old(:, :)
    double precision, intent(out) :: position_new(:, :)

    integer :: i, idx, N, start, p(3)

    N = size(position_old, 2)

    !$omp parallel do private(p, idx, start)
    do i=1, N
       p = this%cartesian_indices(position_old(:,i))
       idx = compact_p_to_h(p, this%M) + 1
       !$omp atomic capture
       start = this%cell_start(idx)
       this%cell_start(idx) = this%cell_start(idx) + 1
       !$omp end atomic
       position_new(:, start) = position_old(:, i)
    end do

  end subroutine sort_particles

  subroutine random_shift(this, state)
    use threefry_module
    implicit none
    class(cell_system_t), intent(inout) :: this
    type(threefry_rng_t), intent(inout) :: state

    this%origin(1) = threefry_double(state) - 1
    this%origin(2) = threefry_double(state) - 1
    this%origin(3) = threefry_double(state) - 1

  end subroutine random_shift

  function cartesian_indices(this, position) result(p)
    class(cell_system_t), intent(in) :: this
    double precision, intent(in) :: position(3)
    integer :: p(3)

    p = floor( (position / this%a) - this%origin )
    if (p(1) == this%L(1)) p(1) = 0
    if (p(2) == this%L(2)) p(2) = 0
    if ( (.not. this%has_walls) .and. (p(3) == this%L(3)) ) p(3) = 0

  end function cartesian_indices

end module cell_system
