program try_all
  use cell_system
  use hilbert
  use tester
  implicit none

  type(cell_system_t) :: solvent_cells
  type(tester_t) :: tester

  integer, parameter :: N = 2000
  double precision, target :: pos1(3, N), pos2(3, N)
  double precision, pointer :: pos(:,:), pos_old(:,:), pos_pointer(:,:)

  integer :: i, L(3), seed_size, clock
  integer, allocatable :: seed(:)
  integer :: h, c1(3), c2(3)

  call tester% init()

  call random_seed(size = seed_size)
  allocate(seed(seed_size))
  call system_clock(count=clock)
  seed = clock + 37 * [ (i - 1, i = 1, seed_size) ]
  call random_seed(put = seed)
  deallocate(seed)

  pos => pos1
  pos_old => pos2

  L = [8, 5, 5]

  call random_number(pos)
  do i = 1, 3
     pos(i, :) = pos(i, :)*L(i)
  end do

  call solvent_cells%init(L, 1.d0)

  call solvent_cells%count_particles(pos)

  call sort
  call solvent_cells%count_particles(pos)

  call tester% assert_equal(solvent_cells%cell_start(1), 1)
  call tester% assert_equal(solvent_cells%cell_start(solvent_cells%N), N+1)
  call tester% assert_equal(sum(solvent_cells%cell_count), N)

  h = 1
  do i = 1, N
     if (i .ge. solvent_cells% cell_start(h) + solvent_cells% cell_count(h)) h = h + 1
     do while (solvent_cells% cell_count(h) .eq. 0)
        h = h+1
     end do
     c1 = floor( (pos(:, i) - solvent_cells% origin) / solvent_cells% a )
     c2 = compact_h_to_p(h-1, solvent_cells% M)
     call tester% assert_equal(c1, c2)
  end do

  call tester% print()

contains

  subroutine sort
    integer :: i, idx, start, p(3)

    call solvent_cells%count_particles(pos)

    do i=1, N
       p = floor( (pos(:, i) - solvent_cells% origin ) / solvent_cells% a )
       idx = compact_p_to_h(p, solvent_cells% M) + 1
       start = solvent_cells% cell_start(idx)
       pos_old(:, start) = pos(:, i)
       solvent_cells% cell_start(idx) = start + 1
    end do

    pos_pointer => pos
    pos => pos_old
    pos_old => pos_pointer

  end subroutine sort

end program try_all