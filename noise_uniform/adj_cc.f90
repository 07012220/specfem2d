program adj_cc

implicit none

! flags
logical, parameter :: use_filtering = .true.
logical, parameter :: use_positive_branch = .false.

! FILTERING PARAMETERS
real  freq_low,freq_high
data  freq_low  / 1d-2 /
data  freq_high / 1d1  /

! WINDOW PARAMETERS
real :: w_delay, w_width, w_tukey
data w_delay / 1.25 /
data w_width / 1.00 /
data w_tukey / 0.4 /
!see explanation of 
!window parameters, below

! time variables
integer :: it, nt, nthalf
double precision :: dt 

! data variables
double precision, dimension(:), allocatable :: seismo_1, seismo_2, seismo_3, seismo_4, &
 seismo_adj, t, w

! input/ output
character(len=64) :: file_in
integer :: ios

! miscellaneous
double precision, parameter :: PI = 3.141592653589793
integer :: it_off, it_wdt, it_begin, it_end, k
integer :: ifreq, nfreq
real :: F1,F2,D(8),G,DELT
real :: alpha, beta




! EXPLANATION OF WINDOW PARAMETERS

!To select the desired branch of the cross-correlogram, we employ a Tukey window.  A Tukey taper is just a variant of a cosine taper.  We use three control parameters

!W_DELAY controls the time offset of the window
!W_WIDTH controls the width of the window (i.e., the total time range over which the window has non-zero support)
!W_TUKEY controls the sharpness of the drop-off 

!In noise tomography applications, W_DELAY should be roughly equal to the surface wave travel time from the one receiver to the other.

!Checks on W_WIDTH are carried out to make sure that the window makes sense and lies within a single branch of the cross-correlogram. If the the window falls outside these bounds, it will be adjusted.

!W_TUKEY is a number between 0 and 1, 0 being pure boxcar and 1 being pure cosine



! Get file info
call getarg(1,file_in)
call getlen(file_in,nt)
call getinc(file_in,nt,dt)
nthalf = (nt+1)/2

write(*,*) ''
write(*,*) 'This routine works only for evenly sampled cross-correlograms.'
write(*,*) 'Reading from file: '//trim(file_in)
write(*,'(a,i10)')   ' nt: ', nt
write(*,'(a,f10.3)') ' dt: ', dt

! Allocate, initialize
allocate(t(nt))
allocate(w(nt))
allocate(seismo_1(nt))
allocate(seismo_2(nt))
allocate(seismo_3(nt))
allocate(seismo_4(nt))
allocate(seismo_adj(nt))
w(:)          = 0.0d0
seismo_1(:)   = 0.0d0
seismo_2(:)   = 0.0d0
seismo_3(:)   = 0.0d0
seismo_4(:)   = 0.0d0
seismo_adj(:) = 0.0d0


!!!!!!!!!! READ INPUT !!!!!!!!!!!!!!!!!!!!
open(unit=1001,file=trim(file_in),status='old',action='read')
do it = 1, nt
    read(1001,*) t(it), seismo_1(nt-it+1)
end do
close(1001)


!!!!!!!!!! DIFFERENTIATE !!!!!!!!!!!!!!!!!!!
seismo_1(1) = 0.0
seismo_1(nt) = 0.0
do it = 2, nt-1
    seismo_2(it) = ( seismo_2(it+1) - seismo_1(it-1) ) / (2*dt)
end do


!!!!!!!!!! FILTER !!!!!!!!!!!!!!!!!!!!
seismo_3 = seismo_2
if (use_filtering) then
! THIS SECTION CALCULATES THE FILTER AND MUST BE CALLED BEFORE          
! FILTER IS CALLED                                                      
DELT = 1.0d3 * dt
F1=freq_low
F2=freq_high
call BNDPAS(F1,F2,DELT,D,G,nt)
!    F1 = LOW FREQUENCY CUTOFF (6 DB DOWN)                             
!    F2 = HIGH FREQUENCY CUTOFF (6 DB DOWN)                             
!    DELT = SAMPLE INTERVAL IN MILLISECONDS                             
!    D = WILL CONTAIN 8 Z DOMAIN COEFICIENTS OF RECURSIVE FILTER        
!    G = WILL CONTAIN THE GAIN OF THE FILTER,
call FILTER(seismo_3,nt,D,G,2)
!    X = DATA VECTOR OF LENGTH N CONTAINING DATA TO BE FILTERED        
!    D = FILTER COEFFICIENTS CALCULATED BY BNDPAS                      
!    G = FILTER GAIN                                                   
!    IG = 1  one pass
!    IG = 2  two passes
end if


!!!!!!!!!! WINDOW !!!!!!!!!!!!!!!!!!!!
it_off = floor(w_delay/dt)
it_wdt = 2*floor(w_width/(2.*dt))
alpha = w_tukey

if (use_positive_branch) then
  write(*,*) 'Choosing positive branch'
  it_begin = nthalf + it_off - it_wdt/2
  it_end   = nthalf + it_off + it_wdt/2
  if (it_begin < nthalf) it_begin = nthalf 
  if (it_end > nt) it_end = nt
else
  write(*,*) 'Choosing negative branch'
  it_begin = nthalf - it_off - it_wdt/2
  it_end   = nthalf - it_off + it_wdt/2
  if (it_begin < 1) it_begin = 1
  if (it_end > nthalf) it_end = nthalf
endif

write(*,'(a,2f10.3)') ' Time range: ', t(1), t(nt)
write(*,'(a,2f10.3)') ' Window:     ', t(it_begin), t(it_end)
write(*,'(a,f10.3,f10.3)') ' Filtering:  ', 1./freq_high, 1./freq_low

!! Tukey taper
k=0
do it = it_begin,it_end
  k=k+1
  beta = real(k-1)/(it_end-it_begin)

  if (beta<alpha/2.) then
    w(it) = 0.5*(1.+cos(2.*pi/alpha*(beta-alpha/2.)))

  elseif (beta>alpha/2. .and. beta<1.-alpha/2.) then
    w(it) = 1.0

  else
    w(it) = 0.5*(1.+cos(2*pi/w_tukey*(beta-1.+alpha/2.)))

  endif
end do
seismo_4 = w * seismo_3


!!!!!!!!!! NORMALIZE !!!!!!!!!!!!!!!!!!!!
seismo_adj = - seismo_4/(DOT_PRODUCT(seismo_4,seismo_4)*dt)


!!!!!!!!!! WRITE ADJOINT SOURCE !!!!!!!!!!!!!!!!!!!!
open(unit=1002,file=trim(file_in)//'.adj',status='unknown',iostat=ios)
if (ios /= 0) write(*,*) 'Error opening output file.'

write(*,*) ''
write(*,*) 'Writing to file: '//trim(file_in)//'.adj'

do it = 1,nt
    write(1002,*), t(it), seismo_adj(it)
end do
close(1002)

write(*,*) 'Finished writing to file.'
write(*,*) ''


end program adj_cc



!=====================================================================
subroutine getlen(filename,len)

implicit none

!input
character(len=64) :: filename

!output
integer :: len

!local
integer, parameter :: IMAX = 1000000
integer :: i,ios
real :: dummy1, dummy2

open(unit=1001,file=trim(filename),status='old',action='read')
len=0
do i=1,IMAX
    read(1001,*,iostat=ios) dummy1, dummy2
    if (ios==-1) exit
    len=len+1
enddo
close(1001)

end subroutine getlen



!=====================================================================
subroutine getinc(filename,len,inc)

implicit none

!input
character(len=64) :: filename
integer :: len

!output
double precision :: inc

!local
integer :: it
double precision, dimension(len) :: t
double precision :: sumdt
real :: dummy

open(unit=1001,file=trim(filename),status='old',action='read')
do it=1,len
    read(1001,*) t(it), dummy
enddo
close(1001)

sumdt = 0.0d0
do it=1,len-1
    sumdt = sumdt + t(it+1) - t(it)
enddo
inc=sumdt/(len-1)

end subroutine getinc


!=====================================================================
SUBROUTINE BNDPAS(F1,F2,DELT,D,G,N)                                         
! RECURSIVE BUTTERWORTH BAND PASS FILTER (KANASEWICH, TIME SERIES       
! ANALYSIS IN GEOPHYSICS, UNIVERSITY OF ALBERTA PRESS, 1975; SHANKS,    
! JOHN L, RECURSION FILTERS FOR DIGITAL PROCESSING, GEOPHYSICS, V32,    
! FILTER.  THE FILTER WILL HAVE 8 POLES IN THE S PLANE AND IS           
! APPLIED IN FORWARD AND REVERSE DIRECTIONS SO AS TO HAVE ZERO          
! PHASE SHIFT.  THE GAIN AT THE TWO FREQUENCIES SPECIFIED AS            
! CUTOFF FREQUENCIES WILL BE -6DB AND THE ROLLOFF WILL BE ABOUT         
! THE FILTER TO PREVENT ALIASING PROBLEMS.                              
    COMPLEX P(4),S(8),Z1,Z2                                           
    real D(8),XC(3),XD(3),XE(3)                            
    double precision :: X(N) 
    DATA ISW/0/,TWOPI/6.2831853/                                      
! THIS SECTION CALCULATES THE FILTER AND MUST BE CALLED BEFORE          
! FILTER IS CALLED                                                      
                                                                       
!    F1 = LOW FREQUENCY CUTOFF (6 DB DOWN)                             
!    F2 = HIGH FREQUENCY CUTOFF (6 DB DOWN)                             
!    DELT = SAMPLE INTERVAL IN MILLISECONDS                             
!    D = WILL CONTAIN 8 Z DOMAIN COEFICIENTS OF RECURSIVE FILTER        
!    G = WILL CONTAIN THE GAIN OF THE FILTER,                           

      DT=DELT/1000.0                                                    
      TDT=2.0/DT                                                        
      FDT=4.0/DT                                                        
      ISW=1                                                             
      P(1)=CMPLX(-.3826834,.9238795)                                    
      P(2)=CMPLX(-.3826834,-.9238795)                                   
      P(3)=CMPLX(-.9238795,.3826834)                                    
      P(4)=CMPLX(-.9238795,-.3826834)                                   
      W1=TWOPI*F1                                                       
      W2=TWOPI*F2                                                       
      W1=TDT*TAN(W1/TDT)                                                
      W2=TDT*TAN(W2/TDT)                                               
      HWID=(W2-W1)/2.0                                                  
      WW=W1*W2                                                          
      DO 19 I=1,4                                                       
      Z1=P(I)*HWID                                                      
      Z2=Z1*Z1-WW                                                       
      Z2=CSQRT(Z2)                                                      
      S(I)=Z1+Z2                                                        
   19 S(I+4)=Z1-Z2                                                      
      G=.5/HWID                                                         
      G=G*G                                                             
      G=G*G                                                             
      DO 29 I=1,7,2                                                     
      B=-2.0*REAL(S(I))                                                 
      Z1=S(I)*S(I+1)                                                    
      C=REAL(Z1)                                                        
      A=TDT+B+C/TDT                                                     
      G=G*A                                                             
      D(I)=(C*DT-FDT)/A                                                 
   29 D(I+1)=(A-2.0*B)/A                                                
      G=G*G                                                           
    5 FORMAT ('-FILTER GAIN IS ', 9E12.6)                                 
      RETURN                                                            

      ENTRY FILTER(X,N,D,G,IG)                                          
                                                                       
!     X = DATA VECTOR OF LENGTH N CONTAINING DATA TO BE FILTERED        
!     D = FILTER COEFFICIENTS CALCULATED BY BNDPAS                      
!     G = FILTER GAIN                                                   
!     IG = 1  one pass
!     ig = 2  two passes
                                                                       
      IF (ISW.EQ.1) GO TO 31                                            
      WRITE (6,6)                                                       
    6 FORMAT ('1BNDPAS MUST BE CALLED BEFORE FILTER')                   
      return                                                            
                                                                       
!     APPLY FILTER IN FORWARD DIRECTION                                 
                                                                       
   31 XM2=X(1)                                                          
      XM1=X(2)                                                          
      XM=X(3)                                                           
      XC(1)=XM2                                                         
      XC(2)=XM1-D(1)*XC(1)                                              
      XC(3)=XM-XM2-D(1)*XC(2)-D(2)*XC(1)                                
      XD(1)=XC(1)                                                       
      XD(2)=XC(2)-D(3)*XD(1)                                            
      XD(3)=XC(3)-XC(1)-D(3)*XD(2)-D(4)*XD(1)                           
      XE(1)=XD(1)                                                       
      XE(2)=XD(2)-D(5)*XE(1)                                            
      XE(3)=XD(3)-XD(1)-D(5)*XE(2)-D(6)*XE(1)                           
      X(1)=XE(1)                                                        
      X(2)=XE(2)-D(7)*X(1)                                              
      X(3)=XE(3)-XE(1)-D(7)*X(2)-D(8)*X(1)                              
      DO 39 I=4,N                                                       
      XM2=XM1                                                           
      XM1=XM                                                            
      XM=X(I)                                                           
      K=I-((I-1)/3)*3                                                   
      GO TO (34,35,36),K                                                
   34 M=1                                                               
      M1=3                                                              
      M2=2                                                              
      GO TO 37                                                          
   35 M=2                                                               
      M1=1                                                              
      M2=3                                                              
      GO TO 37                                                          
   36 M=3                                                               
      M1=2                                                              
      M2=1                                                              
   37 XC(M)=XM-XM2-D(1)*XC(M1)-D(2)*XC(M2)                              
      XD(M)=XC(M)-XC(M2)-D(3)*XD(M1)-D(4)*XD(M2)                        
      XE(M)=XD(M)-XD(M2)-D(5)*XE(M1)-D(6)*XE(M2)                        
   39 X(I)=XE(M)-XE(M2)-D(7)*X(I-1)-D(8)*X(I-2)                         
!                                                                       
!
      if(ig.eq.1) goto 3333                                             
      XM2=X(N)                                                          
      XM1=X(N-1)                                                        
      XM=X(N-2)                                                         
      XC(1)=XM2                                                         
      XC(2)=XM1-D(1)*XC(1)                                              
      XC(3)=XM-XM2-D(1)*XC(2)-D(2)*XC(1)                                
      XD(1)=XC(1)                                                       
      XD(2)=XC(2)-D(3)*XD(1)                                            
      XD(3)=XC(3)-XC(1)-D(3)*XD(2)-D(4)*XD(1)                           
      XE(1)=XD(1)                                                       
      XE(2)=XD(2)-D(5)*XE(1)                                            
      XE(3)=XD(3)-XD(1)-D(5)*XE(2)-D(6)*XE(1)                           
      X(N)=XE(1)                                                        
      X(N-1)=XE(2)-D(7)*X(1)                                            
      X(N-2)=XE(3)-XE(1)-D(7)*X(2)-D(8)*X(1)                            
      DO 49 I=4,N                                                       
      XM2=XM1                                                           
      XM1=XM                                                            
      J=N-I+1                                                           
      XM=X(J)                                                           
      K=I-((I-1)/3)*3                                                   
      GO TO (44,45,46),K                                                
   44 M=1                                                               
      M1=3                                                              
      M2=2                                                              
      GO TO 47                                                          
   45 M=2                                                               
      M1=1                                                              
      M2=3                                                              
      GO TO 47                                                          
   46 M=3                                                               
      M1=2                                                              
      M2=1                                                              
   47 XC(M)=XM-XM2-D(1)*XC(M1)-D(2)*XC(M2)                              
      XD(M)=XC(M)-XC(M2)-D(3)*XD(M1)-D(4)*XD(M2)                        
      XE(M)=XD(M)-XD(M2)-D(5)*XE(M1)-D(6)*XE(M2)                        
   49 X(J)=XE(M)-XE(M2)-D(7)*X(J+1)-D(8)*X(J+2)                         
 3333 continue
      if (ig.eq.1) then
        gg=sqrt(g)   ! if only pass once, modify gain
      else
        gg=g
      endif
      DO 59 I=1,N                                                       
   59 X(I)=X(I)/gg                                                      
      RETURN                                                            
END                                                               

