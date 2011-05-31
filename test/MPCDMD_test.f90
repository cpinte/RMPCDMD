program test
  use sys
  use group
  use LJ
  use MPCD
  use MD
  use ParseText
  use MPCDMD
  use h5md
  use radial_dist
  implicit none
  
  type(PTo) :: CF

  integer :: i_time, i_in, i, istart, reneigh
  integer :: i_MD_time
  integer :: N_MD_loop, N_loop, en_unit
  integer :: flush_unit
  double precision :: max_d, realtime
  character(len=16) :: init_mode
  character(len=2) :: g_string
  integer :: collect_atom, collect_MD_steps, collect_traj_steps
  integer :: seed
  double precision :: at_sol_en, at_at_en, sol_kin, at_kin, energy
  double precision :: lat_0(3), lat_d(3)
  integer :: lat_idx(3), lat_n(3)
  integer :: j
  double precision :: v_sub1(3), v_sub2(3), r_sub1(3), r_sub2(3)
  double precision :: com_g1(3)
  double precision :: total_v(3)
  double precision :: total_kin, total_mass, actual_T, target_T, v_factor, MD_DT
  integer :: N_th_loop
  logical :: reactive, collide, switch

  integer(HID_T) :: file_ID
  type(h5md_t) :: posID
  type(h5md_t) :: enID, so_kinID, at_kinID, at_soID, at_atID, tempID
  type(h5md_t) :: solvent_N_ID
  type(h5md_t) :: vs1ID, vs2ID, rs1ID, rs2ID
  type(h5md_t) :: total_vID
  type(h5md_t) :: colloid_forceID ! the total force on the compound
  double precision :: colloid_f(3)
  integer(HID_T) :: other_ID
  type(h5md_t) :: dset_ID

  double precision :: x_temp(3)
  type(rad_dist_t) :: so_dist, at_dist
  integer, allocatable :: list(:)
  character(len=5) :: zone
  integer :: values(8)

  call MPCDMD_info
  call mtprng_info(short=.true.)
  call PTinfo(short=.true.)

  call PTparse(CF,'sample_MPCDMD',9)

  call h5open_f(h5_error)

  call h5md_create_file(file_ID, 'data.h5', 'MPCDMD')

  seed = PTread_i(CF,'seed')
  if (seed < 0) then
     seed = nint(100*secnds(0.))
  end if
  call h5md_write_par(file_ID, 'seed', seed)
  call mtprng_init(seed, ran_state)

  call config_sys(so_sys,'so',CF)
  call h5md_write_par(file_ID, 'so_Nmax', so_sys % N_max)
  call h5md_write_par(file_ID, 'solvent_N', so_sys % N)
  call config_sys(at_sys,'at',CF)
  call h5md_write_par(file_ID, 'at_Nmax', at_sys % N_max)

  N_groups = PTread_i(CF, 'N_groups')
  call h5md_write_par(file_ID, 'N_groups', N_groups)

  if (N_groups <= 0) stop 'Ngroups is not a positive integer'
  allocate(group_list(N_groups))
  istart = 1
  do i=1,N_groups
     call config_group(group_list(i),i,istart,CF)
     istart = istart + group_list(i)%N
  end do

  

  if (at_sys%N_max<sum(group_list(:)%N)) stop 'at_sys%N_max < # atoms from group_list'

  call config_LJdata(CF, at_sys%N_species, so_sys%N_species)

  call h5md_write_par(file_ID, 'at_so_LJ_eps', at_so % eps)
  call h5md_write_par(file_ID, 'at_so_LJ_sig', at_so % sig)
  call h5md_write_par(file_ID, 'at_at_LJ_eps', at_at % eps)
  call h5md_write_par(file_ID, 'at_at_LJ_sig', at_at % sig)

  call config_MPCD(CF)
  call h5md_write_par(file_ID, 'N_cells', N_cells)
  call h5md_write_par(file_ID, 'cell_unit', a)

  call config_MD
  
  do i=1,N_groups
     if (group_list(i)%g_type == ATOM_G) then
        call config_atom_group(group_list(i))
     else if (group_list(i)%g_type == DIMER_G) then
        call config_dimer_group(group_list(i))
     else if (group_list(i)%g_type == ELAST_G .or. group_list(i)%g_type == SHAKE_G) then
        call config_elast_group(group_list(i))
     else
        stop 'unknown group type'
     end if
  end do
  call h5md_write_par(file_ID, 'group g_type', group_list(:) % g_type)

  do i=1,N_groups
     write(g_string,'(i02.2)') i
     init_mode = PTread_s(CF, 'group'//g_string//'init')
     if (init_mode .eq. 'file') then
        ! load data from file, specifying which group and which file
        init_mode = PTread_s(CF, 'group'//g_string//'file')
        call h5md_open_file(other_ID, init_mode)
        call h5md_open_trajectory(other_ID, 'position', dset_ID)
        call h5md_load_trajectory_data_d(dset_ID, &
             at_r(:, group_list(i)%istart:group_list(i)%istart + group_list(i)%N - 1), -1)
        call h5md_close_ID(dset_ID)
        call h5fclose_f(other_ID, h5_error)
     else if (init_mode .eq. 'random') then
        ! init set group for random init
        write(*,*) 'MPCDMD> WARNING random not yet supported'
     else if (init_mode .eq. 'lattice') then
        ! init set group for lattice init
        lat_0 = PTread_dvec(CF, 'group'//g_string//'lat_0', size(lat_0))
        lat_d = PTread_dvec(CF, 'group'//g_string//'lat_d', size(lat_d))
        lat_n = PTread_ivec(CF, 'group'//g_string//'lat_n', size(lat_n))
        lat_idx = (/ -1, 0, 0 /)
        do j=group_list(i)%istart, group_list(i)%istart + group_list(i)%N - 1
           lat_idx(1) = lat_idx(1) + 1
           if (lat_idx(1) .ge. lat_n(1)) then
              lat_idx(1) = 0
              lat_idx(2) = lat_idx(2) + 1
           end if
           if (lat_idx(2) .ge. lat_n(2)) then
              lat_idx(2) = 0
              lat_idx(3) = lat_idx(3) + 1
           end if
           if (lat_idx(3) .ge. lat_n(3)) then
              lat_idx(3) = 0
           end if
           at_r(:,j) = lat_0 + lat_d * dble(lat_idx)

        end do
              
     else
        write(*,*) 'MPCDMD> unknown init_mode ', init_mode, ' for group'//g_string
        stop 
     end if
  
     if (group_list(i)%g_type == ELAST_G .or. group_list(i)%g_type == SHAKE_G) then
        call config_elast_group2(group_list(i))
        write(*,*) 'group', i, 'configured with', group_list(i)%elast_nlink, 'links'
     end if
  
  end do

  reactive = PTread_l(CF, 'reactive')
  call h5md_write_par(file_ID, 'reactive', reactive)
  if (reactive) then
     do i=1,at_sys % N_species
        do j=1,so_sys % N_species
           call config_reaction(CF, at_so_reac(i,j), i,j)
        end do
     end do
  else
     do i=1,at_sys % N_species
        do j=1,so_sys % N_species
           at_so_reac(i,j) % on = .false.
        end do
     end do
  end if
  so_do_reac = .false.

  collide = PTread_l(CF, 'collide')
  call h5md_write_par(file_id, 'collide', collide)
  switch = PTread_l(CF, 'switch')
  call h5md_write_par(file_id, 'switch', switch)

  !call init_atoms(CF)
  at_v = 0.d0

  write(*,*) so_sys%N_species
  write(*,*) so_sys%N_max
  write(*,*) so_sys%N

  write(*,*) at_sys%N_species
  write(*,*) at_sys%N_max
  write(*,*) at_sys%N

  write(*,*) at_at%eps
  write(*,*) at_at%sig

  write(*,*) at_so%eps
  write(*,*) at_so%sig

  write(*,*) so_species(1:10)
  write(*,*) at_species

  write(*,*) at_so%smooth
  write(*,*) at_at%smooth

  target_T = PTread_d(CF,'so_T')
  call h5md_write_par(file_ID, 'solvent_temperature', target_T)
  call fill_with_solvent( target_T )
  call place_in_cells
  call make_neigh_list

  N_loop = PTread_i(CF, 'N_loop')
  call h5md_write_par(file_ID, 'N_outer_loop', N_loop)
  N_MD_loop = PTread_i(CF, 'N_MD_loop')
  call h5md_write_par(file_ID, 'N_MD_loop', N_MD_loop)
  N_th_loop = PTread_i(CF, 'N_th_loop')
  MD_DT = PTread_d(CF, 'DT')
  DT = MD_DT
  call h5md_write_par(file_ID, 'DT', DT)
  h = PTread_d(CF, 'h')
  collect_atom = PTread_i(CF,'collect_atom')
  collect_MD_steps = PTread_i(CF,'collect_MD_steps')
  collect_traj_steps = PTread_i(CF,'collect_traj_steps')
  do_shifting = PTread_l(CF, 'shifting')

  call PTkill(CF)

  
  at_f => at_f1
  at_f_old => at_f2
  so_f => so_f1
  so_f_old => so_f2

  call compute_f

  en_unit = 11
  open(en_unit,file='energy')
  flush_unit = 12
  open(flush_unit,file='flush_file')
  
  i_time = 0
  i_MD_time = 0
  realtime = 0.d0
  call compute_tot_mom_energy(en_unit, at_sol_en, at_at_en, sol_kin, at_kin, energy, total_v)
  if (allocated(group_list(1) % subgroup) .and. (group_list(1) % N_sub .eq. 2) ) then
     v_sub1 = com_v(group_list(1),1)
     v_sub2 = com_v(group_list(1),2)
     r_sub1 = com_r(group_list(1),1)
     r_sub2 = com_r(group_list(1),2)
  end if
  total_mass = ( sum( so_sys % mass(1:so_sys%N_species) * dble(so_sys % N(1:so_sys%N_species)) ) + &
       sum( at_sys % mass(1:at_sys%N_species) * dble(at_sys % N(1:at_sys%N_species)) ) )
  actual_T = ( sol_kin + at_kin ) *2.d0/3.d0 / total_mass

  call init_rad(so_dist,80,.1d0)
  call init_rad(at_dist,80,.1d0)

  call begin_h5md

  call h5md_set_box_size(posID, (/ 0.d0, 0.d0, 0.d0 /) , L)
  if (allocated(group_list(1)%subgroup) ) then
     call attr_subgroup_h5md(posID, 'subgroups_01', group_list(1)%subgroup)
  end if
  call h5md_write_obs(at_soID, at_sol_en, i_MD_time, realtime)
  call h5md_write_obs(at_atID, at_at_en, i_MD_time, realtime)
  call h5md_write_obs(at_kinID, at_kin, i_MD_time, realtime)
  call h5md_write_obs(so_kinID, sol_kin, i_MD_time, realtime)
  call h5md_write_obs(total_vID, total_v, i_MD_time, realtime)
  call h5md_write_obs(tempID, actual_T, i_MD_time, realtime)
  call h5md_write_obs(enID, energy, i_MD_time, realtime)
  call h5md_write_obs(solvent_N_ID, so_sys % N, i_MD_time, realtime)

  at_jumps = 0

  reneigh = 0
  max_d = min( minval( at_at%neigh - at_at%cut ) , minval( at_so%neigh - at_so%cut ) ) * 0.5d0
  write(*,*) 'max_d = ', max_d

  shift = 0.d0

  DT = MD_DT
  do i_time = 1,N_th_loop
     
     do i_in = 1,N_MD_loop

        at_r_old = at_r

        call MD_step1

        do i=1,N_groups
           if (group_list(i)%g_type .eq. SHAKE_G) then
              call shake(group_list(i))
           end if
        end do

        if ( (maxval( sum( (so_r - so_r_neigh)**2 , dim=1 ) ) > max_d**2) .or. &
             (maxval( sum( (at_r - at_r_neigh)**2 , dim=1 ) ) > max_d**2)) then
           reneigh = reneigh + 1
           call correct_so
           call place_in_cells
           call make_neigh_list
        end if

        call compute_f
        call MD_step2

        do i=1,N_groups
           if (group_list(i)%g_type .eq. SHAKE_G) then
              call rattle(group_list(i))
           end if
        end do

        realtime=realtime+DT
        i_MD_time = i_MD_time + 1


     end do

     call correct_at
     
     if (do_shifting) then
        shift(1) = (mtprng_rand_real1(ran_state)-0.5d0)*a
        shift(2) = (mtprng_rand_real1(ran_state)-0.5d0)*a
        shift(3) = (mtprng_rand_real1(ran_state)-0.5d0)*a
     end if

     call correct_so
     call place_in_cells
     call compute_v_com
     call generate_omega
     call simple_MPCD_step

     total_kin = 0.d0
     total_mass = 0.d0
     do i=1,at_sys%N(0)
        total_mass = total_mass + at_sys % mass( at_species(i) )
        total_kin = total_kin + 0.5d0 * at_sys % mass( at_species(i) ) * sum( at_v(:,i)**2 )
     end do
     do i=1,so_sys%N(0)
        total_mass = total_mass + so_sys % mass( so_species(i) )
        total_kin = total_kin + 0.5d0 * so_sys % mass( so_species(i) ) * sum( so_v(:,i)**2 )
     end do
     actual_T = total_kin * 2.d0/(3.d0 * total_mass )
     v_factor = sqrt( target_T / actual_T )
     at_v = at_v * v_factor
     so_v = so_v * v_factor

     call compute_tot_mom_energy(en_unit, at_sol_en, at_at_en, sol_kin, at_kin, energy, total_v)

     call h5md_write_obs(at_soID, at_sol_en, i_MD_time, realtime)
     call h5md_write_obs(at_atID, at_at_en, i_MD_time, realtime)
     call h5md_write_obs(at_kinID, at_kin, i_MD_time, realtime)
     call h5md_write_obs(so_kinID, sol_kin, i_MD_time, realtime)
     call h5md_write_obs(total_vID, total_v, i_MD_time, realtime)
     call h5md_write_obs(enID, energy, i_MD_time, realtime)
     call h5md_write_obs(tempID, actual_T, i_MD_time, realtime)
     call h5md_write_obs(solvent_N_ID, so_sys % N, i_MD_time, realtime)

     call h5md_write_trajectory_data_d(posID, at_r, i_MD_time, realtime)
  end do

  DT = MD_DT
  do i_time = N_th_loop+1,N_loop+N_th_loop
     
     do i_in = 1,N_MD_loop

        at_r_old = at_r

        call MD_step1

        do i=1,N_groups
           if (group_list(i)%g_type .eq. SHAKE_G) then
              call shake(group_list(i))
           end if
        end do

        if ( (maxval( sum( (so_r - so_r_neigh)**2 , dim=1 ) ) > max_d**2) .or. &
             (maxval( sum( (at_r - at_r_neigh)**2 , dim=1 ) ) > max_d**2)) then
           reneigh = reneigh + 1
           call correct_so
           call place_in_cells
           call make_neigh_list
        end if

        call compute_f
        call MD_step2

        do i=1,N_groups
           if (group_list(i)%g_type .eq. SHAKE_G) then
              call rattle(group_list(i))
           end if
        end do

        if (reactive) call reac_loop

        realtime=realtime+DT
        i_MD_time = i_MD_time + 1

        if ( mod(i_MD_time, collect_MD_steps) .eq. 0 ) then
           if (allocated(group_list(1) % subgroup) .and. (group_list(1) % N_sub .eq. 2) ) then
              v_sub1 = com_v(group_list(1),1)
              v_sub2 = com_v(group_list(1),2)
              r_sub1 = com_r(group_list(1),1)
              r_sub2 = com_r(group_list(1),2)
              call h5md_write_obs(vs1ID, v_sub1, i_MD_time, realtime)
              call h5md_write_obs(vs2ID, v_sub2, i_MD_time, realtime)
              call h5md_write_obs(rs1ID, r_sub1, i_MD_time, realtime)
              call h5md_write_obs(rs2ID, r_sub2, i_MD_time, realtime)
              colloid_f = sum( at_f(:, group_list(1)%istart:group_list(1)%istart+group_list(1)%N-1) , dim=1)
              call h5md_write_obs(colloid_forceID, colloid_f, i_MD_time, realtime)
           end if
        end if

     end do

     call correct_at
     
     if (do_shifting) then
        shift(1) = (mtprng_rand_real1(ran_state)-0.5d0)*a
        shift(2) = (mtprng_rand_real1(ran_state)-0.5d0)*a
        shift(3) = (mtprng_rand_real1(ran_state)-0.5d0)*a
     end if

     com_g1 = com_r(group_list(1))

     call correct_so
     if (collide) then
        call place_in_cells
        call compute_v_com
        call generate_omega
        if (switch) call switch_off(com_g1, 7.d0)
        call simple_MPCD_step
     end if


     call compute_tot_mom_energy(en_unit, at_sol_en, at_at_en, sol_kin, at_kin, energy, total_v)
     
     allocate(list(group_list(1)%N))
     list = (/ ( i, i=group_list(1) % istart, group_list(1) % istart + group_list(1) % N - 1 ) /)
     call update_rad(at_dist, com_g1, at_r, list)
     deallocate(list)

     call list_idx_from_x0(com_g1, 8.d0, list)
     call update_rad(so_dist, com_g1, so_r, list)
     deallocate(list)

     total_mass = ( sum( so_sys % mass(1:so_sys%N_species) * dble(so_sys % N(1:so_sys%N_species)) ) + &
          sum( at_sys % mass(1:at_sys%N_species) * dble(at_sys % N(1:at_sys%N_species)) ) )
     actual_T = ( sol_kin + at_kin ) *2.d0/3.d0 / total_mass

     call h5md_write_obs(at_soID, at_sol_en, i_MD_time, realtime)
     call h5md_write_obs(at_atID, at_at_en, i_MD_time, realtime)
     call h5md_write_obs(at_kinID, at_kin, i_MD_time, realtime)
     call h5md_write_obs(so_kinID, sol_kin, i_MD_time, realtime)
     call h5md_write_obs(total_vID, total_v, i_MD_time, realtime)
     call h5md_write_obs(tempID, actual_T, i_MD_time, realtime)
     call h5md_write_obs(enID, energy, i_MD_time, realtime)
     call h5md_write_obs(solvent_N_ID, so_sys % N, i_MD_time, realtime)

     if (mod(i_time,10).eq.0 .and. reactive) then
        do i=1,so_sys%N(0)
           if (so_species(i) .eq. 2) then
              call rel_pos( so_r(:,i), com_g1, L, x_temp)
              if ( sqrt( sum(x_temp**2) ) > 10.d0 ) then
                 so_sys % N( so_species(i) ) = so_sys % N( so_species(i) ) - 1
                 so_species(i) = 1
                 so_sys % N( so_species(i) ) = so_sys % N( so_species(i) ) + 1
              end if
           end if
        end do
     end if
     if (mod(i_time, collect_traj_steps).eq.0) call h5md_write_trajectory_data_d(posID, at_r, i_MD_time, realtime)

     if (mod(i_time, 100).eq.0) then
        call h5fflush_f(file_ID,H5F_SCOPE_GLOBAL_F, h5_error)
        write(flush_unit, *) 'flushed at i_time ', i_time
        call date_and_time(zone=zone)
        call date_and_time(values=values)
        write(flush_unit, '(i4,a,i2,a,i2,a2,i2,a,i2,a,a5)') &
             values(1),'/',values(2),'/',values(3),'  ',values(5),':', values(6),' ', zone
     end if


  end do


  i_time = i_time-1
  i_MD_time = i_MD_time-1

  call correct_so
  call dump_solvent_species_h5md

  call write_rad(at_dist,file_ID)
  call write_rad(so_dist,file_ID, group_name='solvent')

  call end_h5md

  write(*,*) reneigh, ' extra reneighbourings for ', N_loop*N_MD_loop, ' total steps'

contains
  
  subroutine correct_so
    integer :: i, dim

    do i=1,so_sys%N(0)
       do dim=1,3
          if (so_r(dim,i) < shift(dim)) so_r(dim,i) = so_r(dim,i) + L(dim)
          if (so_r(dim,i) >= L(dim)+shift(dim)) so_r(dim,i) = so_r(dim,i) - L(dim)
       end do
    end do
  end subroutine correct_so

  subroutine correct_at
    integer :: i, dim

    do i=1,at_sys%N(0)
       do dim=1,3
          if (at_r(dim,i) < 0.d0) then
             at_r(dim,i) = at_r(dim,i) + L(dim)
             at_jumps(dim,i) = at_jumps(dim,i) - 1
          end if
          if (at_r(dim,i) >= L(dim)) then
             at_r(dim,i) = at_r(dim,i) - L(dim)
             at_jumps(dim, i) = at_jumps(dim,i) + 1
          end if
       end do
    end do
  end subroutine correct_at

  subroutine switch_off(x0, rcut)
    double precision, intent(in) :: x0(3), rcut

    integer :: ci,cj,ck
    double precision :: x(3)

    do ck=1,N_cells(3)
       do cj=1,N_cells(2)
          do ci=1,N_cells(1)

             call rel_pos(x0-shift, (/ (ci-0.5d0)*a, (cj-0.5d0)*a, (ck-0.5d0)*a /), L, x)
             
             if (sqrt(sum(x**2)) < rcut) par_list(0,ci,cj,ck)=0

          end do
       end do
    end do



  end subroutine switch_off

  subroutine begin_h5md

    call h5md_add_trajectory_data(file_ID, 'position', at_sys% N_max, 3, posID)
    call h5md_create_obs(file_ID, 'energy', enID, energy)
    call h5md_create_obs(file_ID, 'temperature', tempID, actual_T, link_from='energy')
    call h5md_create_obs(file_ID, 'solvent_N', solvent_N_ID, so_sys % N, link_from='energy')
    call h5md_create_obs(file_ID, 'at_at_int', at_atID, at_at_en, link_from='energy')
    call h5md_create_obs(file_ID, 'at_so_int', at_soID, at_sol_en, link_from='energy')
    call h5md_create_obs(file_ID, 'so_kin', so_kinID, sol_kin, link_from='energy')
    call h5md_create_obs(file_ID, 'at_kin', at_kinID, at_kin, link_from='energy')
    call h5md_create_obs(file_ID, 'total_v', total_vID, total_v, link_from='energy')
    if (allocated(group_list(1) % subgroup) .and. (group_list(1) % N_sub .eq. 2) ) then
       call h5md_create_obs(file_ID, 'v_com_1', vs1ID, v_sub1)
       call h5md_create_obs(file_ID, 'v_com_2', vs2ID, v_sub2, link_from='v_com_1')
       call h5md_create_obs(file_ID, 'r_com_1', rs1ID, r_sub1, link_from='v_com_1')
       call h5md_create_obs(file_ID, 'r_com_2', rs2ID, r_sub2, link_from='v_com_1')
       call h5md_create_obs(file_ID, 'colloid_force', colloid_forceID, colloid_f, link_from='v_com_1')
    end if
    call h5md_create_trajectory_group(file_ID, group_name='solvent')
  end subroutine begin_h5md

  subroutine end_h5md
    call h5md_close_ID(posID)
    call h5md_close_ID(enID)
    call h5md_close_ID(tempID)
    call h5md_close_ID(solvent_N_ID)
    call h5md_close_ID(at_atID)
    call h5md_close_ID(at_soID)
    call h5md_close_ID(so_kinID)
    call h5md_close_ID(at_kinID)
    call h5md_close_ID(total_vID)
    if (allocated(group_list(1) % subgroup) .and. (group_list(1) % N_sub .eq. 2) ) then
       call h5md_close_ID(vs1ID)
       call h5md_close_ID(vs2ID)
       call h5md_close_ID(rs1ID)
       call h5md_close_ID(rs2ID)
       call h5md_close_ID(colloid_forceID)
    end if

    call h5fclose_f(file_ID, h5_error)
    
    call h5close_f(h5_error)

  end subroutine end_h5md

  subroutine attr_subgroup_h5md(ID, name, data)
    type(h5md_t), intent(inout) :: ID
    character(len=*), intent(in) :: name
    integer, intent(in) :: data(:,:)

    integer(HID_T) :: a_id, s_id
    integer(HSIZE_T) :: a_size(2)

    a_size = shape(data)
    
    call h5screate_simple_f(2, a_size, s_id, h5_error)
    call h5acreate_f(ID%d_id, name, H5T_NATIVE_INTEGER, s_id, a_id, h5_error)
    call h5awrite_f(a_id, H5T_NATIVE_INTEGER, data-1, a_size, h5_error)
    call h5aclose_f(a_id, h5_error)
    call h5sclose_f(s_id, h5_error)

  end subroutine attr_subgroup_h5md

  subroutine dump_solvent_species_h5md
    integer :: i, ci, cj, ck
    integer :: cc(3)

    integer, allocatable :: temp_list(:,:,:)

    integer(HID_T) :: s_id, d_id, a_id
    integer(HSIZE_T) :: dims(3)
    integer :: rank
    double precision :: data(3)

    allocate(temp_list(N_cells(1),N_cells(2),N_cells(3) ) )

    temp_list = 0

    do i=1,so_sys%N(0)
       cc = floor(so_r(:,i) * oo_a) + 1
       ci = cc(1) ; cj = cc(2) ; ck = cc(3)
       
       if ( ( maxval( (cc-1)/N_cells ) .ge. 1) .or. ( minval( (cc-1)/N_cells ) .lt. 0) ) then
          write(*,*) 'particle', i, 'out of bounds'
       end if
       if (so_species(i).eq.2) then
          temp_list(ci,cj,ck) = temp_list(ci,cj,ck) + 1
       end if
    end do
    
    rank = 3
    dims = N_cells
    call h5screate_simple_f(rank,dims, s_id, h5_error)
    call h5dcreate_f(file_ID, 'trajectory/densityB', H5T_NATIVE_INTEGER, s_id, d_id, h5_error)
    call h5dwrite_f(d_id, H5T_NATIVE_INTEGER, temp_list, dims, h5_error)
    call h5sclose_f(s_id, h5_error)

    rank = 1
    dims(1) = 3
    call h5screate_simple_f(rank,dims, s_id, h5_error)
    call h5acreate_f(d_id, 'x0', H5T_NATIVE_DOUBLE, s_id, a_id, h5_error)
    data = 0.5d0*a
    call h5awrite_f(a_id, H5T_NATIVE_DOUBLE, data, dims, h5_error)
    call h5aclose_f(a_id, h5_error)
    call h5sclose_f(s_id, h5_error)

    call h5screate_simple_f(rank,dims, s_id, h5_error)
    call h5acreate_f(d_id, 'dx', H5T_NATIVE_DOUBLE, s_id, a_id, h5_error)
    data = a
    call h5awrite_f(a_id, H5T_NATIVE_DOUBLE, data, dims, h5_error)
    call h5aclose_f(a_id, h5_error)
    call h5sclose_f(s_id, h5_error)

    call h5dclose_f(d_id, h5_error)

    deallocate(temp_list)

  end subroutine dump_solvent_species_h5md

end program test

