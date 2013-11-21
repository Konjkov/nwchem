      SUBROUTINE AKBKCI(JCMBSPC,IPRINT,
     &           EREF,ERROR_NORM_FINAL,CONV_F)
*
* Outer routine for performing AKBK calculation
*
*. Jeppe Olsen, Febr. 2012, Geneva
*
*                    Oct. 30, 2012; Jeppe Olsen; call to Z_BLKFO changed
* Last modification; July 2013; Jeppe Olsen; AKSIGMA2 path added
*
#include "errquit.fh"
#include "mafdecls.fh"
#include "global.fh"
      INCLUDE 'implicit.inc'
      INCLUDE 'mxpdim.inc'
      INCLUDE 'wrkspc-static.inc'
      INCLUDE 'crun.inc'
      INCLUDE 'glbbas.inc'
      INCLUDE 'cands.inc'
      INCLUDE 'cgas.inc'
      INCLUDE 'akbk.inc'
      INCLUDE 'cshift.inc'
      INCLUDE 'spinfo.inc'
      INCLUDE 'cstate.inc'  
      INCLUDE 'gasstr.inc'
      INCLUDE 'clunit.inc'
      INCLUDE 'cecore.inc'
      INCLUDE 'cprnt.inc'
*
      LOGICAL CONV_F, CONV_LOCAL
      EXTERNAL AKBKSIGMA, AKBKSIGMA2

*
      IDUM = 0
      CALL MEMMAN(IDUM,IDUM,'MARK  ',IDUM,'AKBKCT')
      CALL QENTER('AKBKCT')
 
      WRITE(6,*) ' **************************************'
      WRITE(6,*) ' *                                    *'
      WRITE(6,*) ' * AKBK optimization control entered  *'
      WRITE(6,*) ' *                                    *'
      WRITE(6,*) ' * Version +0.1, Jeppe Olsen, July. 13*'
      WRITE(6,*) ' **************************************'
*
      NTEST = 1000
      NTEST = MAX(NTEST,IPRINT)
*
* Test that CSFs are in use
      IF(NOCSF.EQ.1) THEN
        WRITE(6,*) ' AKBK calculation with determinants is not enabled'
        WRITE(6,*) ' Please remove NOCSF keyword '
        STOP       ' AKBK calculation with determinants is not enabled'
      END IF
      IF(ICNFBAT.EQ.1.OR.ICISTR.EQ.1) THEN
        WRITE(6,*) ' AKBK calculation does not work with incore options'
        WRITE(6,*) ' Please make sure ICNFBAT .ge. 2 and ICISTR .ge. 2 '
        STOP       ' AKBK calculation does not work with incore options'
      END IF
*
      WRITE(6,*) ' Allowed number of outer iterations ', MAXITM
      WRITE(6,*) ' Allowed number of inner iterations ', MAXIT 
*
      IF(IAKBK_MET.EQ.1) THEN
        WRITE(6,*) ' Procedure with Q-vectors on DISC '
      ELSE
        WRITE(6,*) ' Procedure without Q-vectors on DISC '
      END IF
*
      WRITE(6,*) 
     &' Convergence threshold for macroiterations: ', THRES_E
*
*. Memory for summarizer of information
*
      NITEM = 2
      LEN_SUMMARY = NITEM*(MAXITM+1)
      CALL MEMMAN(KL_SUMMARY,LEN_SUMMARY,'ADDL  ',2,'SUMMRY')
      IPSPC = JCMBSPC - 1
      IQSPC = JCMBSPC
      WRITE(6,*) ' P-space for expansion ', IPSPC
      WRITE(6,*) ' Q-space for expansion ', IQSPC
*. Number of CSFs in P and Q
      NPCSF = NCSF_PER_SYM_GN(IREFSM,IPSPC)
      NQCSF = NCSF_PER_SYM_GN(IREFSM,IQSPC)
      IF(NTEST.GE.10) THEN
        WRITE(6,*) ' Initial energy = ', EREF
        WRITE(6,*) ' Number of CSFs in P-space = ', NPCSF
        WRITE(6,*) ' Number of CSFs in PQ-space = ', NQCSF
      END IF
      EREF_INI = EREF
*
* ==================================
* 0: Initial preparation of classes
* ==================================
* 
*
*. The occupation classes of the P-space are those with basespace IPSPC
*. identify and save thise
*
      CALL MEMMAN(KLOCCLS_P,NOCCLS_MAX,'ADDL  ',1,'POCCLS')
      CALL OCCLS_IN_CISPACE(NOCCLS_P,WORK(KLOCCLS_P),
     &       NOCCLS_MAX,int_mb(KIOCCLS),NGAS,
     &       LCMBSPC(IPSPC),ICMBSPC(1,IPSPC),IGSOCCX,IPSPC)
      NCOCCLS = NOCCLS_P
*
*. And the initial identification of the classes in the Q-space
*
      CALL MEMMAN(KLOCCLS_Q,NOCCLS_MAX,'ADDL  ',1,'QOCCLS')
      CALL OCCLS_IN_CISPACE(NOCCLS_Q,WORK(KLOCCLS_Q),
     &       NOCCLS_MAX,int_mb(KIOCCLS),NGAS,
     &       LCMBSPC(IQSPC),ICMBSPC(1,IQSPC),IGSOCCX,IQSPC)
      NSOCCLS = NOCCLS_Q
*. Well the Q-classes may contain terms that are not connected
*. to the P-classes by double excitations. Eliminate these
*
      CALL MEMMAN(KLRCONNECT,NOCCLS_MAX,'ADDL  ',1,'QOCCLS')
C     EXCIT_OCCLS_TO_OCCLS(NOCC_L,IOCC_L,NOCC_R,IOCC_R,
C    &           IOCCLS,NGAS,NEXCIT,NRCONNECT,IRCONNECT)
      MAX_EXCIT = 117
      WRITE(6,*) ' Max excitation level beween P and Q set to',
     &            MAX_EXCIT
      CALL EXCIT_OCCLS_TO_OCCLS(NOCCLS_P,WORK(KLOCCLS_P),
     &    NOCCLS_Q,WORK(KLOCCLS_Q),int_mb(KIOCCLS),NGAS,MAX_EXCIT,
     &    NRCONNECT,WORK(KLRCONNECT))
      IF(NRCONNECT.LT.NOCCLS_Q) THEN
        WRITE(6,*) ' Q-space reduced to interacting occlasses'
        WRITE(6,*) ' Original and new number of Q occlasses ',
     &               NOCCLS_Q, NRCONNECT
        CALL ICOPVE(WORK(KLRCONNECT),WORK(KLOCCLS_P),NRCONNECT)
*. Should also be copied to Sigma occ classes?
      END IF
*
* Info on batches
*
      LBLOCK  = NSD_FOR_OCCLS_MAX
      ICOMP = 0
* Start be letting P be C-space and Q be S-space
      NCOCCLS = NOCCLS_P
      ICSPC = IPSPC
      ICSM = IREFSM
      ILTEST = 3006
      CALL ICOPVE(WORK(KLOCCLS_P),dbl_mb(KCIOCCLS_ACT),NGAS*NOCCLS_P)
      CALL Z_BLKFO_FOR_CISPACE(ICSPC,ICSM,LBLOCK,ICOMP,
     &     IPRNT,NCBLOCK,NCBATCH,
     &     int_mb(KCIOIO),int_mb(KCBLTP),NCOCCLS_ACT,
     &     dbl_mb(KCIOCCLS_ACT),
     &     int_mb(KCLBT),WORK(KCLEBT),WORK(KCLBLK),WORK(KCI1BT),
     &     int_mb(KCIBT),
     &     WORK(KCNOCCLS_BAT),WORK(KCIBOCCLS_BAT),ILTEST)
      NBLOCK_P = NCBLOCK
      NBATCH_P = NCBATCH
      NCBLK = NCBLOCK
      NCM_P = IELSUM(WORK(KCLBLK),NBLOCK_P)
      WRITE(6,*) ' NCM_P = ', NCM_P
*
      NSOCCLS = NOCCLS_Q
      WRITE(6,*) ' NCOCCLS, NSOOCLS in AKBK = ', NCOCCLS, NSOCCLS
      ISSPC = IQSPC
      ISSM = IREFSM
      ILTEST = 3006
      CALL Z_BLKFO_FOR_CISPACE(ISSPC,ISSM,LBLOCK,ICOMP,
     &     IPRNT,NSBLOCK,NSBATCH,
     &     int_mb(KSIOIO),int_mb(KSBLTP),NSOCCLS_ACT,
     &     dbl_mb(KSIOCCLS_ACT),
     &     int_mb(KSLBT),WORK(KSLEBT),WORK(KSLBLK),WORK(KSI1BT),
     &     int_mb(KSIBT),
     &     WORK(KSNOCCLS_BAT),WORK(KSIBOCCLS_BAT),ILTEST)
      NBLOCK_Q = NSBLOCK
      NBATCH_Q = NSBATCH
      NSBLK = NSBLOCK
      WRITE(6,*)  
     & ' Number of blocks and batches in P  ',NBLOCK_P, NBATCH_P
      WRITE(6,*)  
     & ' Number of blocks and batches in PQ ',NBLOCK_Q, NBATCH_Q
*
*. Allocate space: 
*
*. Using the low-disc version, the arrays should be able to hold the 
*. P-expansion (with one block expanded), so
*. The below is a bit sloppy and memory could be reduced
      IF(PSSIGN.EQ.0.0D0) THEN
       LENP = NCM_P
      ELSE
       LENP = 2*NCM_P
      END IF
*
      IF(IAKBK_MET.EQ.2.AND.LENP.GT.LCSBLK) THEN
        WRITE(6,*) 
     &  ' Length of batch will be increased to accomodate P-expansion'
        LCSBLK = LENP
      END IF
      IF(IAKBK_MET.EQ.2) THEN
*.Allocate extra block for incore
        CALL MEMMAN(KVEC4,NSD_FOR_OCCLS_MAX,'ADDL  ',2,'VEC4  ')
      END IF
      CALL GET_3BLKS(KVEC1,KVEC2,KC2)
      KVEC3 = KC2
      KVEC1P = KVEC1
      KVEC2P = KVEC2
*
      I_DO_COMHAM = 0
      IF(I_DO_COMHAM.EQ.1) THEN
         WRITE(6,*) ' Complete Hamiltonian matrix will be constructed '
         NVAR = NPCSF
         CALL MEMMAN(KLHMAT,NVAR*NVAR,'ADDL  ',2,'HMAT  ')
         ECOREL = 0.0D0
C             COMHAM(H,NVAR,NBLOCK,LBLOCK,VEC1,VEC2)
         CALL COMHAM(WORK(KLHMAT),NVAR,NCBLOCK,WORK(KCLBLK),
     &               WORK(KVEC1P),WORK(KVEC2P),ECOREL)
         STOP ' Enforced stop after COMHAM'
      END IF
*
* Preconditioner in P space
*
      LBLK = - 1
*. Obtain Preconditioner in CSF-basis: form determined by IH0_CSF
      WRITE(6,*) ' IH0_CSF = ', IH0_CSF
      IF(IH0_CSF.EQ.1) THEN
*
*  ================
*. Averaged Diagonal
*  ================
*
*. Obtain diagonal over determinants
        CALL REWINO(LUDIA)
        I12 = 2
        SHIFT = ECORE
        IUSE_EXP = 1
        CALL GASDIAT(WORK(KVEC2),LUDIA,SHIFT,ICISTR,I12,
     &               int_mb(KCBLTP),NCBLOCK,int_mb(KCIBT),IUSE_EXP)
        CALL FILEMAN_MINI(LUSC,'ASSIGN')
        CALL CSDIAG(WORK(KVEC1P),WORK(KVEC1P),
     &       NCONF_PER_OPEN(1,IREFSM),MAXOP,IREFSM,
     &       WORK(KSDREO_I(IREFSM)),NPCMCNF,NPCSCNF,IPRCSF,
     &       ICNFBAT,NCOCCLS_ACT,dbl_mb(KCIOCCLS_ACT),
     &       int_mb(KCLBT),LUDIA,LUSC)
        CALL COPVCD(LUSC,LUDIA,WORK(KVEC2P),1,-1)
        CALL FILEMAN_MINI(LUSC,'FREE  ')
      ELSE
*
* ==============================
*. Use exact diagonal or blocks
* ==============================
*
C?      WRITE(6,*) ' Ecore before GET_CSF.... ', ECORE
        NAEL = NELFTP(1) 
        NBEL = NELFTP(2)  
*
        CALL GET_CSF_H_PRECOND(NCONF_PER_OPEN(1,IREFSM),
     &        WORK(KICONF_OCC(IREFSM)),WORK(KVEC1P),ECORE,
     &        LUDIA,NCOCCLS_ACT,dbl_mb(KCIOCCLS_ACT),IREFSM)
C      GET_CSF_H_PRECOND(NCONF_FOR_OPEN,ICONF_OCC,H0,
C     &           ECORE,LUDIA,NOCCLS_SPC,IOCCLS_SPC,ISYM)

C        GET_CSF_H_PRECOND(NEL,NCONF_FOR_OPEN,ICONF_OCC,H0,ECORE,
C    &   IFORM)
      END IF! IH0_CSF switch
*
      MINST = 1
*. Since we are starting our with the solution from the previous space
      IRESTR = 1
      IF(IRESTR.EQ.0) THEN
        INICI = 0
      ELSE
        INICI = -1
      END IF
      LBLK = - 1
      NPRDET = 0
      IPERTOP = 0
      EADD = 0.0D0
*
      KSBEVC = 1
      KSBIDT = 1
      KH0 = 1
      KH0SCR = 1
*
      KLCLSC = 1
      KLCLSE = 1
      KLCLSCT = 1
      KLCLSET = 1
      KLCLSA = 1 
      KLCLSL = 1 
      KLCLSLR = 1 
      KLBLKA = 1
      KLCLSD = 1
      KLCLSDT = 1 
      KLCLSA2 = 1
      KLCBASC = 0
      KLEBASC = 0
      KLBLKCLS = 0
      KLCLSG = 0
      KLCLSGT = 0
*
*. Loop over macroiterations - iterations with fixed energy
*
      EREF_OLD = 3006.56
      CONV_F = .FALSE.
      DO IMAC = 1, MAXITM 
       WRITE(6,*) ' Info from macroiteration ', IMAC
       WRITE(6,*) ' ================================'
       IF(IMAC.GT.1) EREF_OLD = EREF
       SHIFT = - EREF
       IIUSEH0P = 0
       ILAST = -3006
C?     WRITE(6,*) ' IPRCOND = ', IPRECOND  
C?     WRITE(6,*) ' ICISTR, LBLK = ', ICISTR, LBLK
*. An additional file
      CALL FILEMAN_MINI(LU8,'ASSIGN')
      IF(IAKBK_MET.EQ.1) THEN
       CALL CIEIG5(AKBKSIGMA,INICI,EROOT,WORK(KVEC1P),WORK(KVEC2P),
     & MINST,LUDIA,LUC,LUHC,LUSC1,LUSC2,LUSC3,LUSC34,LUSC35,LU8,
     & NVAR,NBLK,NROOT,MXCIV,MAXIT,LUCIVI,IPRDIA,WORK(KSBEVC),
     & NPRDET,WORK(KH0),WORK(KSBIDT),
     & MXP1,MXP2,MXQ,WORK(KH0SCR),EADD,ICISTR,LBLK,
     & IDIAG,dbl_mb(KVEC3),THRES_E,
     & NBATCH,
     & int_mb(KCLBT),WORK(KCLEBT),WORK(KCLBLK),WORK(KCI1BT),
     & int_mb(KCIBT),
     & int_mb(KSLBT),WORK(KSLEBT),WORK(KSLBLK),WORK(KSI1BT),
     & int_mb(KSIBT),
     & INIDEG,E_THRE,C_THRE,
     & E_CONV,C_CONV,ICLSSEL,WORK(KLBLKCLS),NOCCLS,
     & WORK(KLCLSC),WORK(KLCLSE), WORK(KLCLSCT),WORK(KLCLSET),
     & WORK(KLCLSA),WORK(KLCLSL),WORK(KLCLSLR),WORK(KLBLKA),
     & WORK(KLCLSD),WORK(KLCLSDT),WORK(KLCLSG),WORK(KLCLSGT),
     & ISKIPEI,WORK(KC2B),WORK(KLCLSA2),
     & LBLOCK,IROOT_SEL,WORK(KBASSPC),WORK(KLEBASC),
     & WORK(KLCBASC),NCMBSPC,MULSPCA,IPAT,LPAT,ISPC,NCNV_RT,
     & IPRECOND,IIUSEH0P,MPORENP_E,RNRM,CONV_LOCAL,ISBSPPR_ACT,
     & ILAST)
      ELSE
       CALL CIEIG5(AKBKSIGMA2,INICI,EROOT,WORK(KVEC1P),WORK(KVEC2P),
     & MINST,LUDIA,LUC,LUHC,LUSC1,LUSC2,LUSC3,LUSC34,LUSC35,LU8,
     & NVAR,NBLK,NROOT,MXCIV,MAXIT,LUCIVI,IPRDIA,WORK(KSBEVC),
     & NPRDET,WORK(KH0),WORK(KSBIDT),
     & MXP1,MXP2,MXQ,WORK(KH0SCR),EADD,ICISTR,LBLK,
     & IDIAG,dbl_mb(KVEC3),THRES_E,
     & NBATCH,
     & int_mb(KCLBT),WORK(KCLEBT),WORK(KCLBLK),WORK(KCI1BT),
     & int_mb(KCIBT),
     & int_mb(KSLBT),WORK(KSLEBT),WORK(KSLBLK),WORK(KSI1BT),
     & int_mb(KSIBT),
     & INIDEG,E_THRE,C_THRE,
     & E_CONV,C_CONV,ICLSSEL,WORK(KLBLKCLS),NOCCLS,
     & WORK(KLCLSC),WORK(KLCLSE), WORK(KLCLSCT),WORK(KLCLSET),
     & WORK(KLCLSA),WORK(KLCLSL),WORK(KLCLSLR),WORK(KLBLKA),
     & WORK(KLCLSD),WORK(KLCLSDT),WORK(KLCLSG),WORK(KLCLSGT),
     & ISKIPEI,WORK(KC2B),WORK(KLCLSA2),
     & LBLOCK,IROOT_SEL,WORK(KBASSPC),WORK(KLEBASC),
     & WORK(KLCBASC),NCMBSPC,MULSPCA,IPAT,LPAT,ISPC,NCNV_RT,
     & IPRECOND,IIUSEH0P,MPORENP_E,RNRM,CONV_LOCAL,ISBSPPR_ACT,
     & ILAST)
      END IF
*
      CALL FILEMAN_MINI(LU8,'FREE  ')
       EREF = EROOT(NROOT)
       WRITE(6,'(A,F22.12)') '   Energy: ', EREF
       ERROR_NORM_FINAL = RNRM(NROOT)
       WORK(KL_SUMMARY-1+(IMAC-1)*NITEM+1) = ERROR_NORM_FINAL
       WORK(KL_SUMMARY-1+(IMAC-1)*NITEM+2) = EREF
       WRITE(6,'(A,E8.3)') '   Residual norm ',
     & ERROR_NORM_FINAL
*
       DELTA_E = EREF-EREF_OLD
       IF(ABS(DELTA_E).LE.THRES_E.AND.CONV_LOCAL) THEN
         CONV_F = .TRUE.
         GOTO 1001
       END IF
      END DO! loop over macroiterartions
 1001 CONTINUE
*
      IF(CONV_F) THEN
        WRITE(6,*) ' AKBK procedure converged '
        NIT = IMAC
      ELSE
        WRITE(6,*) ' AKBK procedure not converged '
        NIT = IMAC - 1
      END IF
*
      WRITE(6,*)
      WRITE(6,*)
     & ' Iter Residual norm        Energy '
      WRITE(6,*)
     & ' ==============================='
      DO IT = 1, NIT
        ENER =  WORK(KL_SUMMARY-1+(IT-1)*NITEM+2) 
        RNRMI =  WORK(KL_SUMMARY-1+(IT-1)*NITEM+1) 
        WRITE(6,'(1X,I3,4X,E8.3,F20.12)') IT, RNRMI, ENER
      END DO
*
*. Calculate density matrices
*
C?    IF(IDENSI.GE.1)  THEN
C?      WRITE(6,*) ' AKBK_DENSITY will be called '
C?      CALL AKBK_DENSITY(WORK(KRHO1),WORK(KRHO2),WORK(KVEC1),
C?   &       WORK(KVEC2),LUC,EREF,IDENSI)
C            AKBK_DENSITY(RHO1,RHO2,L,R,LUP,E,I12)
C?    END IF
*
      CALL MEMMAN(IDUM,IDUM,'FLUSM ',IDUM,'AKBKCT')
      CALL QEXIT('AKBKCT')
*
      RETURN
      END
      SUBROUTINE EXCIT_OCCLS_TO_OCCLS(NOCC_L,IOCC_L,NOCC_R,IOCC_R,
     &           IOCCLS,NGAS,NEXCIT,NRCONNECT,IRCONNECT)
*
* Two sets, L and R, of occupation classes are given in the 
* form of pointers to the list of occupation classes. 
* Obtain those R classes that are connected to atleast one 
* of the L- classes by atleast a NEXCIT-fold excitation
*
*. Jeppe Olsen
*
      INCLUDE 'implicit.inc'
*. Input
      INTEGER IOCC_L(NOCC_L),IOCC_R(NOCC_R)
      INTEGER IOCCLS(NGAS,*)
*. Output
      INTEGER IRCONNECT(*)
*
      NTEST = 100
      IF(NTEST.GE.10) THEN
        WRITE(6,*)
        WRITE(6,*) ' Output from EXCIT_OCCLS_TO_OCCLS '
        WRITE(6,*) ' ================================='
        WRITE(6,*)
        WRITE(6,*) ' Allowed excitation level = ', NEXCIT
        WRITE(6,*) ' NOCC_R, NOCC_L = ', NOCC_R, NOCC_L
      END IF
*
      NRCONNECT = 0
      DO IIR = 1, NOCC_R
       IR = IOCC_R(IIR)
       IM_CONNECTED = 0
       DO IIL = 1, NOCC_L
        IL = IOCC_L(IIL)
*. Differences in occupations between the classes
        IDIFF = 0
        DO IGAS = 1, NGAS
          IDIFF = IDIFF + ABS(IOCCLS(IGAS,IL)-IOCCLS(IGAS,IR))
        END DO
        IF(IDIFF.LE.2*NEXCIT) IM_CONNECTED = 1
       END DO!loop over IL
       IF(IM_CONNECTED.EQ.1) THEN
         NRCONNECT = NRCONNECT + 1
         IRCONNECT(NRCONNECT) = IR
       END IF
      END DO
*
      IF(NTEST.GE.10) THEN
       WRITE(6,*) ' Number of connected R-classes = ', NRCONNECT
      END IF
      IF(NTEST.GE.1000) THEN
       WRITE(6,*) ' The connected classes '  
       CALL IWRTMA(IRCONNECT,1,NRCONNECT,1,NRCONNECT)
      END IF
*
      RETURN
      END
      SUBROUTINE AKBKSIGMA(CB,HCB,LUC,LUHC)
*. 
*. Obtain AKBK Hamiltonian times a vector on LUC
*
* A P and a Q space has been defined, so the eigenvalue problem reads:
*
* ( H(PP)    H(PQ) ) (CP)        (CP)
* (                ) (  )   = E  (  )
* ( H(QP)    H(QQ) ) (CQ)        (CQ)
* 
* Lowdin partition the matrix to obtain
*
* [(HPP - H(PQ) (H(QQ) - E )^(-1)H(QP)]CP = E CP
*
* HQQ is assumed so simple it may be diagonalized - here
* Diagonal or block diagonal over 
*
*. Input and output vectors are supposed to be in P-space(?)
*
*. It is assumed that ICNFBAT = 2, NOCSF = 0 has been checked outside
*
*. Jeppe Olsen, Geneva, Febr. 2012 (20 hours before take-off)
*
#include "errquit.fh"
#include "mafdecls.fh"
#include "global.fh"
      INCLUDE 'implicit.inc'
      INCLUDE 'mxpdim.inc'
      INCLUDE 'wrkspc-static.inc'
      INCLUDE 'glbbas.inc'
      INCLUDE 'cstate.inc'
      INCLUDE 'cshift.inc'
      INCLUDE 'akbk.inc'
      INCLUDE 'lucinp.inc'
      INCLUDE 'cgas.inc'
      INCLUDE 'cands.inc'
      INCLUDE 'crun.inc'
*
      LBLK = -1
*
      IDUM = 1
      CALL MEMMAN(IDUM,IDUM,'MARK  ',1,'AKBKSI')
      CALL QENTER('AKBKSI')
      NTEST = 10
      IF(NTEST.GE.10) THEN
        WRITE(6,*) ' Information from AKBKSIGMA'
        WRITE(6,*) ' =========================='
        WRITE(6,*)
      END IF 
      IF(NTEST.GE.100) THEN
        WRITE(6,*) ' LUC, LUHC = ', LUC, LUHC
      END IF
      IF(NTEST.GE.1000) THEN
        WRITE(6,*) ' Input vector to AKBKSIGMA '
        CALL WRTVCD(CB,LUC,1,LBLK)
      END IF
*
*
*. Scratch files for C and Sigma in determinant basis, HQP CP, (HQQ-E) HQP CP
* 
      CALL FILEMAN_MINI(LU_Q1,'ASSIGN')
      CALL FILEMAN_MINI(LU_Q2,'ASSIGN')
      CALL FILEMAN_MINI(LU_Q3,'ASSIGN')
*
*. Calculate HQP CP in PQ space and save on LU_Q2
*
      ICSPC = IPSPC
      ISSPC = IQSPC
      CALL REWINO(LUC)
      CALL REWINO(LU_Q2)
      CALL MV7(CB,HCB,LUC,LU_Q2,XDUM,XDUM)
      IF(NTEST.GE.1000) WRITE(6,*) ' H(QP)P CP accomplished'
      IF(NTEST.GE.1000) THEN
       CALL WRTVCD(CB,LU_Q2,1,LBLK)
      END IF
*
*. Well really, we wanted HQP CP only in Q space, remove P space terms, to LU_Q1
*
*. Array giving dimensions of occlass for given sym
      CALL MEMMAN(KLLOCCLS_SM,NOCCLS_MAX,'ADDL  ',1,'OC_LSM')
      IF(NTEST.GE.1000) WRITE(6,*) ' ISSM, NIRREP = ', ISSM, NIRREP
C          EXTRROW(WORK(KLCIBT),8,8,NBLOCK,LBLOCK)
      CALL EXTRROW(int_mb(KNCS_FOR_OCCLS),ISSM,NIRREP,NOCCLS_MAX,
     &             WORK(KLLOCCLS_SM))
      IF(NTEST.GE.1000) THEN
        WRITE(6,*) ' Number of CSF of right sym per occls'
        CALL IWRTMA(WORK(KLLOCCLS_SM),1,NOCCLS_MAX,1,NOCCLS_MAX)
      END IF
*
      CALL EXP_BLKVEC(LU_Q2,NOCCLS_P,WORK(KLOCCLS_P),
     &                LU_Q1,NOCCLS_Q,WORK(KLOCCLS_Q),
     &                WORK(KLLOCCLS_SM),2,CB,XDUM,1,ICISTR,0)
*
C     EXP_BLKVEC(LU_IN,NBLK_IN, IBLK_IN,
C    &                      LU_OUT,NBLK_OUT,IBLK_OUT,
C    &                      LBLK,ITASK,VEC,VEC_OUT,IREW,ICISTR,
C    &                      INCORE)
      IF(NTEST.GE.1000) WRITE(6,*) ' HQP CP  calculated'
*
*. Calculate diagonal(HQQ) and save on LU_Q3
*
      CALL CSDIAGM(IREFSM,2,LU_Q3,CB,HCB)
*
*. (HQQ - E)**-1 HQP CP on LU_Q2
*
      IPRECOND = 1
      LBLK = -1 
      IPNTR = 0
      H0 = 3006.56
      H0SCR = 3006.56
      IZERO = 0
      IF(NTEST.GE.1000) WRITE(6,*) ' Shift :', SHIFT 
      CALL H0M1TD(LU_Q2,LU_Q3,LU_Q1,LBLK,IZERO,IPNTR,
     &     H0,SHIFT,H0SCR,XH0IX,
     &     IZERO,IZERO,IZERO,CB,HCB,NTEST,IPRECOND)
*      H0M1TD(LUOUT,LUDIA,LUIN,LBLK,NPQDM,IPNTR,
       IF(NTEST.GE.1000) WRITE(6,*) ' Apres H0M1TD '
       CALL MEMCHK2('APH0M1')
       IF(NTEST.GE.1000) THEN
        WRITE(6,*) ' (HQQ - E)**-1 HQP CP '
        CALL WRTVCD(CB,LU_Q2,1,LBLK)
       END IF
       
*
*. Multiply (HQQ - E)**-1 HQP CP (LU_Q2) with HQP and save on LU_Q3
*
      ISSPC = IPSPC
      ICSPC = IQSPC
      XDUM = 3006.56
      CALL REWINO(LU_Q3)
      CALL MV7(CB,HCB,LU_Q2,LU_Q3,XDUM,XDUM)
      IF(NTEST.GE.1000) THEN
        WRITE(6,*) ' HPQ (HQQ - E)**-1 HQP CP  '
        CALL WRTVCD(CB,LU_Q3,1,LBLK)
      END IF
*
* Obtain HPP CP and save on LU_Q1
*
      ISSPC = IPSPC
      ICSPC = IPSPC
      CALL REWINO(LU_Q1)
      CALL MV7(CB,HCB,LUC,LU_Q1,XDUM,XDUM)
      IF(NTEST.GE.1000) THEN
        WRITE(6,*) ' HPP CP: '
        CALL WRTVCD(CB,LU_Q1,1,LBLK)
      END IF
*
* And the grand finale: 
*
* [(HPP - H(PQ) (H(QQ) - E )^(-1)H(QP)]CP
      ONE = 1.0D0
      ONEM = -1.0D0
C VECSMD(VEC1,VEC2,FAC1,FAC2, LU1,LU2,LU3,IREW,LBLK)
      LBLK = -1
      CALL VECSMD(CB,HCB,ONE,ONEM,LU_Q1,LU_Q3,LUHC,1,LBLK)
*
      IF(NTEST.GE.1000) THEN
       WRITE(6,*) ' Sigma vector from AKBKSIGMA:'
       CALL WRTVCD(CB,LUHC,1,LBLK)
      END IF
*
      CALL FILEMAN_MINI(LU_CDET,'FREE  ')
      CALL FILEMAN_MINI(LU_SDET,'FREE  ')
      CALL FILEMAN_MINI(LU_Q1,'FREE  ')
      CALL FILEMAN_MINI(LU_Q2,'FREE  ')
      CALL FILEMAN_MINI(LU_Q3,'FREE  ')
*
      IF(NTEST.GE.10) WRITE(6,*) ' Leaving AKBKSIGMA'
C?    WRITE(6,*) ' Jeppe forced me to stop.... '
C?    STOP ' Jeppe forced me to stop.... '
      CALL MEMMAN(IDUM,IDUM,'FLUSM ',1,'AKBKSI')
      CALL QEXIT('AKBKSI')
*
      RETURN
      END
      SUBROUTINE CSDIAGM(ISM,ICS,LUDIA_A,VECUT,VECSCR)
*
* Set up the CSF preconditioner in CI space ISPC 
* and save on VECUT or LUDIA_A. It is assumed that the relevant block-and
* class info has been obtained and is stored in the KC*, KS*, or 
* KE arrays * (ICS=1,2,3, respectively)
*
*. Jeppe Olsen, Febr. 2012, Geneva, 8 hours before take off.
*  Last modification; Jeppe Olsen; July 29, 2013; ICISTR = 1 and ICS = 3 option added
*
* Incore requires: ICISTR = 1 + ICNFBAT = 1
*
#include "errquit.fh"
#include "mafdecls.fh"
#include "global.fh"
      INCLUDE 'implicit.inc'
      INCLUDE 'mxpdim.inc'
      INCLUDE 'wrkspc-static.inc'
      INCLUDE 'glbbas.inc'
      INCLUDE 'cgas.inc'
      INCLUDE 'crun.inc'
      INCLUDE 'cecore.inc'
      INCLUDE 'spinfo.inc'
      INCLUDE 'cands.inc'
      INCLUDE 'cprnt.inc'
      INCLUDE 'ceblk.inc'
*
      CALL QENTER('CSDIAM')
*
      NTEST = 000
      IF(NTEST.GE.100) THEN 
        WRITE(6,*) ' Entering CSDIAGM '
        WRITE(6,*) ' ================='
        WRITE(6,*) ' IH0_CSF, ICS = ', IH0_CSF, ICS
      END IF
*
      IF(ICS.NE.1.AND.ICS.NE.2.AND.ICS.NE.3) THEN
        WRITE(6,*) ' Illegal value of ICS in CSDIAGM = ', ICS
        STOP       ' Illegal value of ICS in CSDIAGM  '
      END IF
*
      IF(IH0_CSF.EQ.1) THEN
*
*  ================
*. Averaged Diagonal
*  ================
*
*. Obtain diagonal over determinants on a scratch file
*
        IF(ICISTR.NE.1) THEN
          CALL FILEMAN_MINI(LUSC,'ASSIGN')
          CALL REWINO(LUSC)
        ELSE
          LUSC = -1
        END IF
*
        I12 = 2
        SHIFT = ECORE
        IUSE_EXP = 1
*
        IF(ICS.EQ.1) THEN
          KXBLTP = KCBLTP
          KXIBT  = KCIBT
          NXBLOCK = NCBLK
        ELSE IF(ICS.EQ.2) THEN
          KXBLTP = KSBLTP
          KXIBT  = KSIBT
          NXBLOCK = NSBLK
        ELSE IF (ICS.EQ.3) THEN
*. use info from ceblk.inc
          KXBLTP = KEBLTP
          KXIBT = KEIBT
          NXBLOCK = NEBLK
        ELSE
          WRITE(6,*) ' Illegal value of ICS in CSDIAGM', ICS
          STOP       ' Illegal value of ICS in CSDIAGM'
        END IF
        IUSE_EXP = 1
        IF(NTEST.GE.1000)
     &  WRITE(6,*) ' NCBLK, NSBLK, NXBLOCK = ', NCBLK, NSBLK, NXBLOCK
        CALL GASDIAT(VECSCR,LUSC,SHIFT,ICISTR,I12,
     &               int_mb(KXBLTP),NXBLOCK,int_mb(KXIBT),IUSE_EXP)
*
* Average diagonal in each configuration
*
        IF(ICS.EQ.1) THEN
          NXIOCCLS_ACT = NCOCCLS
          KXIOCCLS_ACT = KCIOCCLS_ACT
          KXLBT = KCLBT
        ELSE IF(ICS .EQ. 2) THEN
          NXIOCCLS_ACT = NSOCCLS
          KXIOCCLS_ACT = KSIOCCLS_ACT
          KXLBT = KSLBT
        ELSE IF (ICS. EQ. 3) THEN
          NXIOCCLS_ACT = NEOCCLS
          KXIOCCLS_ACT = KEIOCCLS_ACT
          KXLBT = KELBT
        END IF
*
        CALL CSDIAG(VECUT,VECSCR,
     &       NCONF_PER_OPEN(1,ISM),MAXOP,ISM,
     &       WORK(KSDREO_I(ISM)),NPCMCNF,NPCSCNF,IPRCSF,
     &       ICNFBAT,NXIOCCLS_ACT,dbl_mb(KXIOCCLS_ACT),
     &       int_mb(KXLBT),LUSC,LUDIA_A)
        IF(ICISTR.NE.1) CALL FILEMAN_MINI(LUSC,'FREE  ')
      ELSE
*
* ==============================
*. Use exact diagonal or blocks
* ==============================
*
        IF(ICS.EQ.1) THEN
          NXIOCCLS_ACT = NCOCCLS
          KXIOCCLS_ACT = KCIOCCLS_ACT
        ELSE 
          NXIOCCLS_ACT = NSOCCLS
          KXIOCCLS_ACT = KSIOCCLS_ACT
        END IF
*
C?      WRITE(6,*) ' Ecore before GET_CSF.... ', ECORE
        CALL GET_CSF_H_PRECOND(NCONF_PER_OPEN(1,ISM),
     &        WORK(KICONF_OCC(ISM)),VECUT,ECORE,
     &        LUDIA_A,NXIOCCLS_ACT,dbl_mb(KXIOCCLS_ACT),ISM)
      END IF! IH0_CSF switch
      CALL QEXIT('CSDIAM')
*
      RETURN
      END
      SUBROUTINE GET_CQ_FROM_CP(LUCP,LUCQ,E,CB,HCB)
*
* Obtain CQ = - (HQQ - E)**(-1) CP
*
* With CP stored on LUCP and result stored at LUCQ
* ( Jeppe is in his systematic mode today....)
*
* Jeppe Olsen, Aug. 23, 2012, in Minneapolis
*
#include "errquit.fh"
#include "mafdecls.fh"
#include "global.fh"
      INCLUDE 'implicit.inc'
      INCLUDE 'mxpdim.inc'
      INCLUDE 'wrkspc-static.inc'
      INCLUDE 'glbbas.inc'
      INCLUDE 'cstate.inc'
      INCLUDE 'cshift.inc'
      INCLUDE 'akbk.inc'
      INCLUDE 'lucinp.inc'
      INCLUDE 'cgas.inc'
      INCLUDE 'cands.inc'
      INCLUDE 'crun.inc'
*. Scratch blocks required to hold largest blocks..
      DIMENSION CB(*), HCB(*)
*
      LBLK = -1
*
      IDUM = 1
      CALL MEMMAN(IDUM,IDUM,'MARK  ',1,'GET_CQ')
      CALL QENTER('GET_CQ')
      NTEST = 10000
      IF(NTEST.GE.10) THEN
        WRITE(6,*) ' Information from GET_CQ'
        WRITE(6,*) ' =========================='
        WRITE(6,*)
        WRITE(6,*) ' LUCP, LUCQ = ', LUCP, LUCQ
        WRITE(6,*) ' IPSPC, IQSPC = ', IPSPC, IQSPC
      END IF
      IF(NTEST.GE.1000) THEN
        WRITE(6,*) ' Input vector to GET_CQ_FROM_CP '
        CALL WRTVCD(CB,LUCP,1,LBLK)
      END IF
*
*
*. Scratch files for C and Sigma in determinant basis, HQP CP, (HQQ-E) HQP CP
* 
      CALL FILEMAN_MINI(LU_Q1,'ASSIGN')
      CALL FILEMAN_MINI(LU_Q2,'ASSIGN')
      CALL FILEMAN_MINI(LU_Q3,'ASSIGN')
*
*. Calculate HQP CP in PQ space and save on LU_Q2
*
      ICSPC = IPSPC
      ISSPC = IQSPC
      CALL REWINO(LUCP)
      CALL REWINO(LU_Q2)
      CALL MV7(CB,HCB,LUCP,LU_Q2,XDUM,XDUM)
      IF(NTEST.GE.1000) WRITE(6,*) ' H(QP) CP accomplished'
      IF(NTEST.GE.1000) THEN
       WRITE(6,*) ' H(QP) CP: '
       CALL WRTVCD(CB,LU_Q2,1,LBLK)
      END IF
*
*. Well really, we wanted HQP CP only in Q space, remove P space terms, 
*. save on LU_Q1
*
*. Array giving dimensions of occlass for given sym
      CALL MEMMAN(KLLOCCLS_SM,NOCCLS_MAX,'ADDL  ',1,'OC_LSM')
      IF(NTEST.GE.1000) WRITE(6,*) ' ISSM, NIRREP = ', ISSM, NIRREP
C          EXTRROW(WORK(KLCIBT),8,8,NBLOCK,LBLOCK)
      CALL EXTRROW(int_mb(KNCS_FOR_OCCLS),ISSM,NIRREP,NOCCLS_MAX,
     &             WORK(KLLOCCLS_SM))
      IF(NTEST.GE.1000) THEN
        WRITE(6,*) ' Number of CSF of right sym per occls'
        CALL IWRTMA(WORK(KLLOCCLS_SM),1,NOCCLS_MAX,1,NOCCLS_MAX)
      END IF
*
      CALL EXP_BLKVEC(LU_Q2,NOCCLS_P,WORK(KLOCCLS_P),
     &                LU_Q1,NOCCLS_Q,WORK(KLOCCLS_Q),
     &                WORK(KLLOCCLS_SM),2,CB,XDUM,1,ICISTR,0)
*
C     EXP_BLKVEC(LU_IN,NBLK_IN, IBLK_IN,
C    &                      LU_OUT,NBLK_OUT,IBLK_OUT,
C    &                      LBLK,ITASK,VEC,VEC_OUT,IREW,ICISTR,
C    &                      INCORE)
      IF(NTEST.GE.1000) WRITE(6,*) ' HQP CP  calculated'
      IF(NTEST.GE.10000) THEN
       WRITE(6,*) ' H(QP) CP with P-terms removed: '
       CALL WRTVCD(CB,LU_Q1,1,LBLK)
      END IF
*
*. Calculate diagonal(HQQ) and save on LU_Q3
*
C          CSDIAGM(ISM,ICS,LUDIA_A)
C          CSDIAGM(ISM,ICS,LUDIA_A,VECUT,VECSCR)
      CALL CSDIAGM(IREFSM,2,LU_Q3,CB,HCB)
*
*. (HQQ - E)**-1 HQP CP on LU_Q2
*
      IPRECOND = 1
      LBLK = -1 
      IPNTR = 0
      H0 = 3006.56
      H0SCR = 3006.56
      IZERO = 0
      SHIFT = -E 
      IF(NTEST.GE.1000) WRITE(6,*) ' Shift :', SHIFT 
      CALL H0M1TD(LU_Q2,LU_Q3,LU_Q1,LBLK,IZERO,IPNTR,
     &     H0,SHIFT,H0SCR,XH0IX,
     &     IZERO,IZERO,IZERO,CB,HCB,NTEST,IPRECOND)
*     H0M1TD(LUOUT,LUDIA,LUIN,LBLK,NPQDM,IPNTR,
      IF(NTEST.GE.1000) WRITE(6,*) ' Apres H0M1TD '
      CALL MEMCHK2('APH0M1')
      IF(NTEST.GE.1000) THEN
       WRITE(6,*) ' (HQQ - E)**-1 HQP CP '
       CALL WRTVCD(CB,LU_Q2,1,LBLK)
      END IF
*. And the minus -1
      ONEM = -1.0D0
C SCLVCD(LUIN,LUOUT,SCALE,SEGMNT,IREW,LBLK)
      CALL SCLVCD(LU_Q2,LUCQ,ONEM,CB,1,-1)
*
      IF(NTEST.GE.1000) THEN
        WRITE(6,*) ' The CQ vector '
        WRITE(6,*) ' ============= '
        CALL WRTVCD(CB,LUCQ,1,LBLK)
      END IF
*
      CALL FILEMAN_MINI(LU_Q1,'FREE')
      CALL FILEMAN_MINI(LU_Q2,'FREE')
      CALL FILEMAN_MINI(LU_Q3,'FREE')
*
      CALL MEMMAN(IDUM,IDUM,'FLUSM ',1,'GET_CQ')
      CALL QEXIT('GET_CQ')
*
      RETURN
      END
      SUBROUTINE GET_APPROX_DEN_AKBK_QQ(RHO1_QQ, RHO2_QQ,LUP,E,
     &                                 CB,HCB,I12)
*
* Obtain approximate densities for QQ interaction in AKBK approach
* for the Q vector corresponding of the P-vector given on LU_P
*
* The approximite densities are - those used to calculate energy, i.e.
*
*  RHO1_QQ(ij) = delta(ij) <0Q| E_ii |0Q>
*  RHO2_QQ(ijkl) = delta(ij)delta(kl) <0Q|E_ii E_kk |0Q>
*                 -delta(il)delta(kj) <0Q|a+is ais a+js ajs|0Q> (if I12 = 2)
*
*. Jeppe Olsen, Aug. 23, 2012 in Minneapolis
*
#include "errquit.fh"
#include "mafdecls.fh"
#include "global.fh"
      INCLUDE 'implicit.inc'
      INCLUDE 'mxpdim.inc'
      INCLUDE 'wrkspc-static.inc'
      INCLUDE 'orbinp.inc'
      INCLUDE 'glbbas.inc'
      INCLUDE 'akbk.inc'
      INCLUDE 'stinf.inc'
      INCLUDE 'gasstr.inc'
      INCLUDE 'strinp.inc'
      INCLUDE 'crun.inc'
      INCLUDE 'cicisp.inc'
      INCLUDE 'spinfo.inc'
      INCLUDE 'cands.inc'
*. Output: Standard form of densities
      DIMENSION RHO1_QQ(*), RHO2_QQ(*)
*. Scratch for holding blocks of vectors
      DIMENSION CB(*), HCB(*)
*
      CALL MEMMAN(IDUM,IDUM,'MARK ',1,'AKQQDN')
      CALL QENTER('AKQQCN')
* Some files
      CALL FILEMAN_MINI(LUQ,'ASSIGN')
      CALL FILEMAN_MINI(LUQ1,'ASSIGN')
*
*. 1: Generate the Q-vector from the given P-vector
*
C         GET_CQ_FROM_CP(LUCP,LUCQ,E,CB,HCB)
      CALL GET_CQ_FROM_CP(LUP,LUQ,E,CB,HCB)
*
*. Transform Q from CSF to SD basis and store on LUQ1
* 
*. requires some 
      IATP = 1
      IBTP = 2
*
      NOCTPA = NOCTYP(IATP)
      NOCTPB = NOCTYP(IBTP)
*
      IOCTPA = IBSPGPFTP(IATP)
      IOCTPB = IBSPGPFTP(IBTP)
*
      NAEL = NELEC(IATP)
      NBEL = NELEC(IBTP)
*. Block for storing complete or partial CI-vector
      IF(ISIMSYM.EQ.0) THEN
        LBLOCK = MXSOOB
      ELSE
        LBLOCK = MXSOOB_AS
      END IF
      IF(NOCSF.EQ.0) THEN
        LBLOCK  = MAX(NSD_FOR_OCCLS_MAX,MXSOOB)
      END IF
      LBLOCK = MAX(LBLOCK,LCSBLK)
      IF(NTEST.GE.100) THEN
        WRITE(6,*) ' TEST, LCSBLK, LBLOCK, MXSOOB  = ',
     &                     LCSBLK, LBLOCK, MXSOOB
      END IF
      ICOMP = 0
      
      CALL Z_BLKFO_FOR_CISPACE(IQSPC,ICSM,LBLOCK,ICOMP,
     &     NTEST,NQBLOCK,NQBATCH,
     &     int_mb(KCIOIO),int_mb(KCBLTP),NQOCCLS_ACT,
     &     dbl_mb(KCIOCCLS_ACT),
     &     int_mb(KCLBT),WORK(KCLEBT),WORK(KCLBLK),WORK(KCI1BT),
     &     int_mb(KCIBT),
     &     WORK(KCNOCCLS_BAT),WORK(KCIBOCCLS_BAT),0,ILTEST)

      CALL CSDTVCMN(CB,HCB,dbl_mb(KVEC3),
     &     1,0,ICSM,IQSPC,2,2,LUQ1,LUQ,NQOCCLS_ACT,
     &     dbl_mb(KCIOCCLS_ACT),int_mb(KCIBT),int_mb(KCLBT))
*
* 3: Generate diagonal contribitions to the density
*
      CALL DIAG_DET_TO_DENSI(CB,LUQ1,int_mb(KCBLTP),
     &     NQBLOCK,int_mb(KCIBT),RHO1_QQ, RHO2_QQ,I12)
C     DIAG_DET_TO_DENSI(CB,LUC,IBLTP,NBLOCK,IBLKFO,
C    &                             RHO1D,RHO2D,I12)
*
*. Clean up time
      CALL FILEMAN_MINI(LU_Q,'FREE')
      CALL FILEMAN_MINI(LU_Q1,'FREE')
      CALL MEMMAN(IDUM,IDUM,'FLUSM',1,'AKQQDN')
      CALL QEXIT('AKQQCN')
*
      RETURN
      END
      SUBROUTINE DIAG_DET_TO_DENSI(CB,LUC,IBLTP,NBLOCK,IBLKFO,
     &                             RHO1D,RHO2D,I12)
*
*
* Diagonal contribution from determinants to one-and two-electron
* densities
* Jeppe Olsen, August 23, 2012
* Last revision, August 23 2012, Jeppe Olsen
*
c      IMPLICIT REAL*8(A-H,O-Z)
* =====
*.Input
* =====
*
*./ORBINP/: NACOB used
*
      INCLUDE 'implicit.inc'
      INCLUDE 'mxpdim.inc'
      INCLUDE 'wrkspc-static.inc'
      INCLUDE 'orbinp.inc'
      INCLUDE 'cicisp.inc'
      INCLUDE 'strbas.inc'
      INCLUDE 'cstate.inc' 
      INCLUDE 'strinp.inc'
      INCLUDE 'stinf.inc'
      INCLUDE 'csm.inc'
      INCLUDE 'cprnt.inc'
      INCLUDE 'cgas.inc'
      INCLUDE 'gasstr.inc'
      INCLUDE 'glbbas.inc'
*
      DIMENSION IBLTP(*)
      DIMENSION IBLKFO(8,NBLOCK)
*
* ======
*.Output
* ======
      DIMENSION RHO1D(*), RHO2D(*)
*
      IDUM = 0
      CALL QENTER('DIARHO')
      CALL MEMMAN(IDUM,  IDUM,    'MARK  ',IDUM,'DIARHO')
*
      NTEST = 1000
*
** Specifications of alpha - and beta types
*
      IATP = 1
      IBTP = 2
      NAEL = NELEC(IATP)
      NBEL = NELEC(IBTP)
      NOCTPA = NOCTYP(IATP)
      NOCTPB = NOCTYP(IBTP)
      IOCTPA = IBSPGPFTP(IATP)
      IOCTPB = IBSPGPFTP(IBTP)
*
      IF(NTEST.GE.10) THEN
        WRITE(6,*) ' ==========================='
        WRITE(6,*) ' DIAG_DET_TO_DENSI speaking '
        WRITE(6,*) ' ==========================='
*
        WRITE(6,*) ' IATP IBTP NAEL NBEL = ',IATP,IBTP,NAEL,NBEL
        write(6,*) ' NOCTPA NOCTPB = ', NOCTPA,NOCTPB
        write(6,*) ' IOCTPA IOCTPB = ', IOCTPA,IOCTPB
      END IF
*
**. Local memory
*
      IDUM = 0
*. Space for blocks of strings
      MAXA = IMNMX(int_mb(KNSTSO(IATP)),NSMST*NOCTPA,2)
      MAXB = IMNMX(int_mb(KNSTSO(IBTP)),NSMST*NOCTPB,2)
      CALL MEMMAN(KLASTR,MAXA*NAEL,'ADDL  ',1,'KLASTR')
      CALL MEMMAN(KLBSTR,MAXB*NBEL,'ADDL  ',1,'KLBSTR')
*
      CALL DIAG_DET_TO_DENSIS(NAEL,WORK(KLASTR),NBEL,WORK(KLBSTR),
     &       NACOB,CB,NSMST,int_mb(KNSTSO(IATP)),int_mb(KNSTSO(IBTP)),
     &       LUC,IPRDIA,ICISTR,IBLTP,NBLOCK,IBLKFO,RHO1D,RHO2D,I12)

*.Flush local memory
      CALL MEMMAN(IDUM,  IDUM,    'FLUSM ',IDUM,'DIARHO')
      CALL QEXIT('DIARHO')
*
      RETURN
      END
      SUBROUTINE DIAG_DET_TO_DENSIS(NAEL,IASTR,NBEL,IBSTR,
     &           NACOB,CB,NSMST,NSSOA,NSSOB,LUC,IPRNT,ICISTR,
     &           IBLTP,NBLOCK,IBLKFO,RHO1D,RHO2D,I12)
*
* Diagonal contributions to density matrix
*
* Jeppe Olsen, Aug. 23, Minneapolis
*
* Last revision, Aug 23 - 2012, Jeppe Olsen
*
      INCLUDE 'implicit.inc'
*.Input
      DIMENSION NSSOA(NSMST,*),NSSOB(NSMST,*)
      DIMENSION IBLTP(*),IBLKFO(8,NBLOCK)
*
*. Scratch
      DIMENSION IASTR(NAEL,*),IBSTR(NBEL,*), CB(*)
*. Output
      DIMENSION RHO1D(*), RHO2D(*) 
*
      NTEST = 1000
*
      IF( NTEST .GE. 100) THEN
*
        WRITE(6,*) ' TTSS for Blocks '
        DO IBLOCK = 1, NBLOCK               
          WRITE(6,'(10X,4I3,2I8)') (IBLKFO(II,IBLOCK),II=1,4)
        END DO
*
        WRITE(6,*) ' IBLTP: '
        CALL IWRTMA(IBLTP,1,NSMST,1,NSMST)
        WRITE(6,*) ' I12 = ',I12
      END IF
*
      ITDET = 0
      LBLK = -1
      IF(LUC.NE.0) CALL REWINO(LUC)
*
      DO IBLK = 1, NBLOCK
*
        IATP = IBLKFO(1,IBLK)
        IBTP = IBLKFO(2,IBLK)
        IASM = IBLKFO(3,IBLK)
        IBSM = IBLKFO(4,IBLK)
        IF(NTEST.GE.1000) WRITE(6,*) ' IBLK,IATP,IBTP,IASM,IBSM=',
     &  IBLK,IATP,IBTP,IASM,IBSM
*. Read block of C in 
        IF( ICISTR.GE.2 ) THEN
*. Read in a Type-Type-symmetry block
          CALL IFRMDS(IDET,1,-1,LUC)
          NO_ZEROING = 0
          CALL FRMDSC2(CB,IDET,-1,LUC,IMZERO,IAMPACK,NO_ZEROING)
          IF(NTEST.GE.1000)
     &    WRITE(6,*) ' Number of elements readin ',IDET
          IDET = 0
        END IF
        IF(NTEST.GE.1000) WRITE(6,*) 'a: IBLK,IATP,IBTP,IASM,IBSM=',
     &  IBLK,IATP,IBTP,IASM,IBSM
*. Obtain beta strings of sym IBSM and type IBTP
        CALL GETSTR_TOTSM_SPGP(2,IBTP,IBSM,NBEL,NBSTR1,IBSTR,
     &                         NORB,0,IDUM,IDUM)
        IF(NTEST.GE.1000) WRITE(6,*) 'b: IBLK,IATP,IBTP,IASM,IBSM=',
     &  IBLK,IATP,IBTP,IASM,IBSM
*. Read block of C in 
        CALL GETSTR_TOTSM_SPGP(1,IATP,IASM,NAEL,NASTR1,IASTR,
     &                           NORB,0,IDUM,IDUM)
*
        IF(IBLTP(IASM).EQ.2) THEN
          IREST1 = 1
        ELSE
          IREST1 = 0
        END IF

        IBSTRT = 1                
        IBSTOP =  NSSOB(IBSM,IBTP)
        DO IB = IBSTRT,IBSTOP
          IBREL = IB - IBSTRT + 1
*
          IF(IREST1.EQ.1.AND.IATP.EQ.IBTP) THEN
            IASTRT =  IB
            IREST2 = 1
          ELSE
            IASTRT = 1                 
            IREST2 = 0
          END IF
          IASTOP = NSSOA(IASM,IATP) 
*
          DO IA = IASTRT,IASTOP
            IDET = IDET + 1
            WRITE(6,*) ' IDET = ', IDET
            COEF = CB(IDET)
            WRITE(6,*) ' COEF = ', COEF
            IF(IREST2.EQ.0.OR.IA.EQ.IB) THEN
             WEIGHT = COEF**2
            ELSE
             WEIGHT = 2.0D0*COEF**2
            END IF
            IF(NTEST.GE.1000) WRITE(6,*) ' IA, IB, WEIGHT =',
     &      IA,IB, WEIGHT
*
*. Alpha contributions
*
            DO IAEL = 1, NAEL
              I = IASTR(IAEL,IA)
              II = (I-1)*NACOB + I
              RHO1D(II) = RHO1D(II) + WEIGHT
            END DO
*
*. beta contributions
*
            DO IBEL = 1, NBEL
              I = IBSTR(IBEL,IB)
              II = (I-1)*NACOB + I
              RHO1D(II) = RHO1D(II) + WEIGHT
            END DO
*
*alpha-alpha contributions
*
            IF(I12.EQ.2) THEN
             DO IAEL1 = 1, NAEL
             DO IAEL2 = 1, IAEL1
               I = IASTR(IAEL1,IA)
               K = IASTR(IAEL2,IA)
               II = (I-1)*NACOB + I
               KK = (K-1)*NACOB + I
               IIKK = II*(II-1)/2 + KK
               RHO2D(IIKK) =  RHO2D(IIKK) + WEIGHT
               IK = (K-1)*NACOB + I
               KI = (I-1)*NACOB + K
               KIIK = KI*(KI-1)/2 + IK
               RHO2D(KIIK) = RHO2D(KIIK) - WEIGHT
             END DO
             END DO
*
*beta-beta contributions
*
             DO IBEL1 = 1, NBEL
             DO IBEL2 = 1, IBEL1
               I = IBSTR(IBEL1,IB)
               K = IBSTR(IBEL2,IB)
               II = (I-1)*NACOB + I
               KK = (K-1)*NACOB + I
               IIKK = II*(II-1)/2 + KK
               RHO2D(IIKK) =  RHO2D(IIKK) + WEIGHT
               IK = (K-1)*NACOB + I
               KI = (I-1)*NACOB + K
               KIIK = KI*(KI-1)/2 + IK
               RHO2D(KIIK) = RHO2D(KIIK) - WEIGHT
             END DO
             END DO
*
* Alpha-beta contributions
*
             DO IAEL = 1, NAEL
             DO IBEL = 1, NBEL
               I = IASTR(IAEL,IA)
               K = IBSTR(IBEL,IB)
               II = (I-1)*NACOB + I
               KK = (K-1)*NACOB + I
               IF(II.GE.KK) THEN
                 IIKK = II*(II-1)/2 + KK
                 RHO2D(IIKK) =  RHO2D(IIKK) + WEIGHT
               END IF
               IK = (K-1)*NACOB + I
               KI = (I-1)*NACOB + K
               IF(KI.GE.IK) THEN
                 KIIK = KI*(KI-1)/2 + IK
                 RHO2D(KIIK) = RHO2D(KIIK) - WEIGHT
               END IF
             END DO
             END DO
            END IF ! I12 = 2
          END DO
*         ^ End of loop over alpha strings
        END DO
*       ^ End of loop over betastrings
      END DO
*     ^ End of loop over blocks
*
      IF(NTEST.GE.1000) THEN
        WRITE(6,*) ' Output from DIAG_DET_TO_DENSIS: '
        WRITE(6,*) ' --------------------------------' 
        WRITE(6,*)
        WRITE(6,*) ' Updated one-electron density '
        CALL WRTMAT(RHO1D,NACOB,NACOB,NACOB,NACOB)
        WRITE(6,*) ' Updated two-electron density '
        NAA = NACOB*(NACOB+1)/2
        CALL PRSYM(RHO2D,NAA)
      END IF
*
      RETURN
      END
      SUBROUTINE AKBK_DENSITY(RHO1,RHO2,L,R,LUP,E,I12)
*
* Obtain AKBK 1- and 2-body density(I12 = 2) matrices
*
*. Jeppe Olsen, Aug. 23 - 2012, Jeppe Olsen
* Last revision: Aug. 23 -2012, Jeppe Olsen
*
* The AKBK densities are given as 
*
* RHO1(ij) = <0^P!E_ij!0^P> + <0^Q!E_ij!0^P>  + <0^P!E_ij!0^Q> +
*               + Delta(ij) <0^Q!E_ii!0^Q> 
* 
* RHO2(ij,kl) = <0^P!E_ijE_kl - \delta(jk)E_il!0^P> 
*             + <0^P!E_ijE_kl - \delta(jk)E_il!0^Q> 
*             + <0^Q!E_ijE_kl - \delta(jk)E_il!0^P> 
*             + Delta(ij)delta(kl)  <0^Q!E_iiE_kk - \delta(jk)E_ik!0^Q>
*
*
#include "errquit.fh"
#include "mafdecls.fh"
#include "global.fh"
      INCLUDE 'implicit.inc'
      INCLUDE 'mxpdim.inc'
      INCLUDE 'orbinp.inc'
      INCLUDE 'cicisp.inc'
      INCLUDE 'strbas.inc'
      INCLUDE 'cstate.inc'
      INCLUDE 'akbk.inc'
      INCLUDE 'wrkspc-static.inc'
*. Output
      DIMENSION RHO1(*),RHO2(*)
*. Two scratch blocks
      REAL*8 L(*), R(*)
*
      NTEST = 1000
      IF(NTEST.GE.100) THEN
        WRITE(6,*) ' AKBK_DENSITY at your service '
        WRITE(6,*) ' ============================='
      END IF
*
      LBLK = -1
      CALL QENTER('AKBK_D')
      CALL MEMMAN(IDUMMY,IDUMMY,'MARK  ', IDUMMY,'AKBK_D')
*. Local copies of Rho1 and Rho2
      LRHO1 = NACOB**2
      LRHO2 = (NACOB**2+1)*NACOB**2/2
      CALL MEMMAN(KLRHO1,LRHO1,'ADDL  ',2,'RHO1_L')
      CALL MEMMAN(KLRHO1B,LRHO1,'ADDL  ',2,'RHO1_B')
      IF(I12.EQ.2) THEN
        CALL MEMMAN(KLRHO2,LRHO2,'ADDL  ',2,'RHO2_L')
        CALL MEMMAN(KLRHO2B,LRHO2,'ADDL  ',2,'RHO2_L')
      END IF
*. And a few local files
      CALL FILEMAN_MINI(LUSC1,'ASSIGN')
      CALL FILEMAN_MINI(LUSC2,'ASSIGN')
      CALL FILEMAN_MINI(LUSC3,'ASSIGN')
*
*   Obtain P-P densities 
*  
C COPVCD(LUIN,LUOUT,SEGMNT,IREW,LBLK)
      CALL COPVCD(LUP,LUSC1,CB,1,LBLK)
C     DENSI2(I12,RHO1,RHO2,L,R,LUL,LUR,EXPS2,IDOSRHO12,SRHO1,
C    &                  RHO2AA,RHO2AB,RHO2BB,IDONATORB)
      ICSPC = IPSPC
      ISSPC = IPSPC
      CALL DENSI2(I12,RHO1,RHO2,L,R,LUP,LUSC1,EXPS2,0,XDUM,
     &            XDUM,XDUM,XDUM,0)
*
*   Obtain P-Q densities 
*  
*. Q vector
      CALL GET_CQ_FROM_CP(LUP,LUSC1,E,L,R)
C     GET_CQ_FROM_CP(LUCP,LUCQ,E,CB,HCB)
      ISSPC = IPSPC
      ICSPC = IQSPC
      WRITE(6,*) ' DENSI2 will be called for PQ density '
      CALL DENSI2(I12,WORK(KLRHO1),WORK(KLRHO2),L,R,LUSC1,LUP,EXPS2,0,
     &     XDUM,XDUM,XDUM,XDUM,0)
      ONE = 1.0D0
      CALL VECSUM(RHO1,RHO1,WORK(KLRHO1),ONE,ONE,LRHO1)
      IF(I12.EQ.2)
     &CALL VECSUM(RHO2,RHO2,WORK(KLRHO2),ONE,ONE,LRHO2)
*
* Obtain Q-P densities - from  P-Q densities
*
      CALL TRPMAT(WORK(KLRHO1),NACOB,NACOB,WORK(KLRHO1B))
      CALL VECSUM(RHO1,RHO1,WORK(KLRHO1B),ONE,ONE,LRHO1)
      IF(I12.EQ.2) THEN
        CALL CONJ_RHO2(NACOB,WORK(KLRHO2),WORK(KLRHO2B))
        CALL VECSUM(RHO2,RHO2,WORK(KLRHO2B),ONE,ONE,LRHO2)
      END IF
*
* And then to the interesting: the Q-Q density
*
C     GET_APPROX_DEN_AKBK_QQ(RHO1_QQ, RHO2_QQ,LUP,E,CB,HCB,I12) 
      CALL GET_APPROX_DEN_AKBK_QQ(WORK(KLRHO1),WORK(KLRHO2),LUP,E,
     &    L,R,I12)
*
      IF(NTEST.GE.1000) THEN
       WRITE(6,*) ' AKBK densities '
       WRITE(6,*) ' -------------- '
       WRITE(6,*) 
       WRITE(6,*) ' AKBK-rho1 '
       CALL WRTMAT(RHO1,NACOB,NACOB,NACOB,NACOB)
       IF(I12.EQ.2) THEN
         WRITE(6,*)
         WRITE(6,*) ' AKBK-rho2 '
         LAA = NACOB**2
         CALL PRSYM(RHO2,LAA)
       END IF
      END IF
*
      CALL MEMMAN(IDUMMY,IDUMMY,'FLUSM ', IDUMMY,'AKBK_D')
      CALL QEXIT('AKBK_D')
*
      RETURN
      END
      SUBROUTINE CONJ_RHO2(NACOB,RHO2_IN,RHO2_UT)
*
*. Conjugate two-electron density matrix RHO2_IN to obtain
*. RHO2_UT
* RHO2_UT(ji,lk) = RHO2_IN(ij,kl)
*
*. Jeppe Olsen, Aug. 23 2012, Minneapolis
*
      INCLUDE 'implicit.inc'  
*. Input
      DIMENSION RHO2_IN(*)
*. Output 
      DIMENSION  RHO2_UT(*)
*
      NTEST = 100
      IF(NTEST.GE.100) THEN
        WRITE(6,*) ' Info from CONJ_RHO2'
        WRITE(6,*) ' ==================='
      END IF
*
      DO J = 1, NACOB
       DO I = 1, NACOB
        JI = (I-1)*NACOB + J
        IJ = (J-1)*NACOB + I
        DO L = 1, J
         IF(L.EQ.J) THEN
           KMAX = I
         ELSE
           KMAX = NACOB
         END IF
         DO K = 1, KMAX
           LK = (K-1)*NACOB + L
           KL = (L-1)*NACOB + K
           IF(IJ.GE.KL) THEN
             IJKL = IJ*(IJ-1)/2 + KL
           ELSE
             IJKL = KL*(KL-1)/2 + IJ
           END IF
           JILK = JI*(JI-1)/2 + KL
           RHO2_UT(JILK) = RHO2_IN(IJKL)
         END DO ! K
        END DO ! L
       END DO ! J
      END DO ! I
*
      IF(NTEST.GE.1000) THEN
        WRITE(6,*) ' RHO2_IN: '
        LAA = NACOB**2
        CALL PRSYM(RHO2_IN,LAA)
        WRITE(6,*) ' RHO2_UT: '
        CALL PRSYM(RHO2_UT,LAA) 
      END IF
*
      RETURN
      END
      SUBROUTINE GET_FIA2(F2,FIA,IFIA2_OFFSS)
*
* Obtain First-order expansion matrix of FI + FA
*
* FIA(kappa)_mn = FIA(0)_mn + sum_(p>q) F2_mn,pq Kappa_pq, m geq n, p gt q
* m and n, as well as p and q, have identical symmetries
*
* F2_mn,pq  =  2 \delta(q,m) FIA_pn  + 2\delta(q,n) FIA_mp 
*           -  2 \delta(p,m) FIA_mq  - 2\delta(p,n) FIA_mq
*           +  (\delta(q,inactive) (4 (mn!pq) - (mp!qn)-(mq!pn))
*           -  (\delta(p,inactive) (4 (mn!qp) - (mq!pn)-(mp!qn))
*           +  (\delta(q,active) (Q(mnpq) + Q(nmpq))
*           -  (\delta(p,active) (Q(mnqp) + Q(nmqp))
*
* where Q(mnpq) =\sum_w (g(mnpw) - g(mqpn) D(qw) (q active)
*
*. Jeppe Olsen, Aug. 23, 2012, Minneapolis
*. Last revision: aug 24- 2012, Jeppe Olsen
*
*. Indeces corresponds to symmetry-type order, i.e. same order as integrals.
      INCLUDE 'implicit.inc'
      INTEGER P,Q,PM, PN,QM,QN, PQ, PT, QT
      INCLUDE 'mxpdim.inc'
      INCLUDE 'glbbas.inc'
      INCLUDE 'orbinp.inc'
      INCLUDE 'wrkspc-static.inc'
      INCLUDE 'lucinp.inc'
*. Input
      DIMENSION FIA(*)
*. Output
      DIMENSION F2(*)
      INTEGER IFIA2_OFFSS(NSMOB,NSMOB)
*
      NTEST = 100
      IF(NTEST.GE.100) THEN
       WRITE(6,*)
       WRITE(6,*) ' Info from  GET_FIA2 '
       WRITE(6,*) ' =================== '
       WRITE(6,*)
      END IF
*
      IDUM = 0
      CALL MEMMAN(IDUM,IDUM,'MARK  ',IDUM,'F2MAT ')
      CALL QENTER('F2MAT')
*. Dimension of F2
      NR = 0
      NC = 0
      DO ISM = 1, NSMOB
        NR = NR + NTOOBS(ISM)*(NTOOBS(ISM)+1)/2
        NC = NC + NTOOBS(ISM)*(NTOOBS(ISM)-1)/2
      END DO
*. Offset to blocks of F with given symmetry of MN, PQ
      IMNPQ_OFF = 1
      DO IPQSM = 1, NSMOB
       DO IMNSM = 1, NSMOB
         NMN = NTOOBS(IMNSM)*(NTOOBS(IMNSM)+1)/2
         NPQ = NTOOBS(IPQSM)*(NTOOBS(IPQSM)-1)/2
         IFIA2_OFFSS(IMNSM,IPQSM) = IMNPQ_OFF
         IMNPQ_OFF = IMNPQ_OFF + NMN*NPQ
       END DO
      END DO
*
      ZERO = 0.0D0
      TWO = 2.0D0
      CALL SETVEC(F2,ZERO,NR*NC)
*
* =================
*. The delta terms
* =================
*
*. Contributes only to symmetry blocks with IMNSM = IPQSM - all four indeces have identical sym
      DO ISM = 1, NSMOB
       IF2_OFF =  IFIA2_OFFSS(ISM,ISM)
*. Offset to this symmetry block in FIA
       IF1_OFF = 1
       DO IISM = 1, ISM-1
        IF1_OFF = IF1_OFF + NTOOBS(IISM)*(NTOOBS(IISM)+1)/2
       END DO
*
       NO = NTOOBS(ISM)
       NOOR = NO*(NO+1)/2
       NOOC = NO*(NO-1)/2
*
*. Term1: 2 FIA_pn to F2(MN,PM)
*
       DO M = 1, NO
        DO N = 1, M
         DO P = M+1, NO
           MN = M*(M+1)/2 + N
           PM = (P-1)*(P-2)/2 + M
           MNPM = (PM-1)*NOOR + MN
           NP_F1 = (P-1)*(P-2)/2 + N
           F2(IF2_OFF-1+MNPM) = F2(IF2_OFF-1+MNPM) 
     &                        + TWO*FIA(IF1_OFF-1+NP_F1)
         END DO
        END DO
       END DO
*
* Term 2: 2FIA_mp to F2(MN,PN)
*
       DO M = 1, NO
        DO N = 1, M
         DO P = N+1, NO
          MN = M*(M-1)/2 + N
          PN = (P-1)*(P-2)/2 + N
          MNPN = (PN-1)*NOOR + MN
          MP_F1 = MAX(M,P)*(MAX(M,P)-1)/2 + MIN(M,P)
          F2(IF2_OFF-1+MNPN) =  F2(IF2_OFF-1+MNPN) 
     &                       + TWO*FIA(IF1_OFF-1+MP_F1)
         END DO
        END DO
       END DO
*
* Term 3: - 2FIA_qn to F2(MN,MQ)
*
       DO M = 1, NO
        DO N = 1, M
         DO Q = 1, M-1
          MN = M*(M-1)/2 + N
          MQ = (M-1)*(M-2)/2 + Q
          MNMQ = (MQ-1)*NOOR + MN
          NQ_F1 = MAX(N,Q)*(MAX(N,Q)-1)/2 + MIN(N,Q)
          F2(IF2_OFF-1+MNMQ) =  F2(IF2_OFF-1+MNMQ)  
     &                       - TWO*FIA(IF1_OFF+NQ_F1)
         END DO
        END DO
       END DO
*
* Term 4: -2FIA_mq to F2(MN,NQ)
*
       DO M = 1, NO  
        DO N = 1, NO
         DO Q = 1, N-1
           MN = M*(M-1)/2 + N
           NQ = (N-1)*(N-2)/2 + Q
           MNNQ = (NQ-1)*NOOR + MN
           MQ_F1 = M*(M-1)/2 + Q
           F2(IF2_OFF-1+MNNQ) =  F2(IF2_OFF-1+MNNQ)  
     &                        - TWO*FIA(IF1_OFF+MQ_F1)
         END DO
        END DO
       END DO
*
      END DO ! End of symmetry blocks of F2
*
* ==================================================================
* The terms
*           +  (\delta(q,inactive) (4 (mn!pq) - (mp!qn)-(mq!pn))
*           -  (\delta(p,inactive) (4 (mn!qp) - (mq!pn)-(mp!qn))
* ==================================================================
*
      DO IMNSM = 1, NSMOB
       DO IPQSM = 1, NSMOB
        NMN = NTOOBS(IMNSM)
        NPQ = NTOOBS(IPQSM)
        NOOR = NMN*(NMN+1)/2
        IF2_OFF =  IFIA2_OFFSS(IMNSM,IPQSM)
        DO M = 1, NMN
         DO N = 1, M
          DO P = 1, NPQ
           DO Q = 1, P-1
             IF(ITPFSO(Q).EQ.0) THEN
*. Q is Inactive 
               MN = M*(M-1)/2 + N
               PQ = (P-1)*(P-2)/2 + Q
               MNPQ = (PQ-1)*NOOR + MN
               MT = IREOST(M)
               NT = IREOST(N)
               PT = IREOST(P)
               QT = IREOST(Q)
C  4 (mn!pq) - (mp!qn)-(mq!pn))
               X = 4.0D0* GTIJKL_GN(MT,NT,PT,QT)-GTIJKL_GN(MT,PT,QT,NT)
     &           - GTIJKL_GN(MT,QT,PQ,NT)
               F2(MNPQ) = F2(MNPQ) + X
             END IF
             IF(ITPFSO(P).EQ.0) THEN
*. P is inactive
               MN = M*(M-1)/2 + N
               PQ = (P-1)*(P-2)/2 + Q
               MNPQ = (PQ-1)*NOOR + MN
               MT = IREOST(M)
               NT = IREOST(N)
               PT = IREOST(P)
               QT = IREOST(Q)
C   -(4 (mn!qp) - (mq!pn)-(mp!qn))
               X = 4.0D0*GTIJKL_GN(MT,NT,QT,PT) 
     &           - GTIJKL_GN(MT,QT,PT,NT)
     &           - GTIJKL_GN(MT,PT,QT,NT)
                F2(MNPQ) = F2(MNPQ) - X
             END IF
*
            END DO
           END DO
          END DO
         END DO ! loop over M,N,P,Q
        END DO
       END DO ! loop over IMNSM, IPQSM
*. The terms 
*     +  (\delta(q,active) (Q(mnpq) + Q(nmpq))
*     -  (\delta(p,active) (Q(mnqp) + Q(nmqp))
* with  Q(mnpq) =\sum_w (g(mnpw) - g(mqpn) D(qw) (q active)
*
*
      LQ = 0
      DO IMNSM = 1, NSMOB
       DO IPQSM = 1, NSMOB
        LQ = LQ + NTOOBS(IMNSM)**2*NTOOBS(IPQSM)*NACOBS(IPQSM)
       END DO
      END DO
      CALL MEMMAN(KLQ,LQ,'ADDL  ',2,'QMAT  ')
      CALL MEMMAN(KLQP,NSMOB**2,'ADDL  ',1,'IQ_OFF')
      CALL GET_QMAT(WORK(KLQ),WORK(KLQP))
      IOFFQ = 1
      IOFFF = 1
      DO IMNSM = 1, NSMOB
        DO IPQSM = 1, NSMOB
         NMN = NTOOBS(IMNSM)
         NOOR = NMN*(NMN+1)/2
         DO M = 1, NMN
          DO N = 1, NMN
           MN = M*(M-1)/2 + N
* +  (\delta(q,active) (Q(mnpq) + Q(nmpq))
           NQINA = NINOBS(IPQSM)
           DO P = 1, NTOOBS(IPQSM)
            DO Q = NQINA+1, MIN(NQINA + NACOBS(IMNSM),P)
              PQ = (P-1)*(P-2)/2 + Q
              MNPQ_F = (PQ-1)*NOOR + MN
              MNPQ_Q = (Q-NQINA-1)*NMN**2*NTOOBS(IPQSM)
     &               + (P-1)      *NMN**2
     &               + (N-1)      *NMN
     &               + M
              F2(IOFFF-1+MNPQ_F) = 
     &        F2(IOFFF-1+MNPQ_F)  + WORK(KLQ-1+IOFFQ-1+MNPQ_Q)
              NMPQ_Q = (Q-NQINA-1)*NMN**2*NTOOBS(IPQSM)
     &               + (P-1)      *NMN**2
     &               + (M-1)      *NMN
     &               + N
              F2(IOFFF-1+MNPQ_F) = 
     &        F2(IOFFF-1+MNPQ_F) + WORK(KLQ-1+IOFFQ-1+NMPQ_Q)
            END DO
           END DO ! Loops over pq
*     -  (\delta(p,active) (Q(mnqp) + Q(nmqp))
           DO P = NINOBS(IPQSM)+1, NINOBS(IPQSM)+NACOBS(IPQSM)
            NPINA = NINOBS(IPQSM)
            DO Q = 1, P
              PQ = (P-1)*(P-2)/2 + Q
              MNPQ_F = (PQ-1)*NOOR + MN
              MNQP_Q = (P-NQINA-1)*NMN**2*NTOOBS(IPQSM)
     &               + (Q-1)      *NMN**2
     &               + (N-1)      *NMN
     &               + M
              F2(IOFFF-1+MNPQ_F) = 
     &        F2(IOFFF-1+MNPQ_F)  + WORK(KLQ-1+IOFFQ-1+MNQP_Q)
              NMQP_Q = (P-NQINA-1)*NMN**2*NTOOBS(IPQSM)
     &               + (Q-1)      *NMN**2
     &               + (M-1)      *NMN
     &               + N
              F2(IOFFF-1+MNPQ_F) = 
     &        F2(IOFFF-1+MNPQ_F) + WORK(KLQ-1+IOFFQ-1+NMQP_Q)
            END DO
           END DO ! Loops over pq
*
          END DO
         END DO ! loops over MN
         IOFFQ = IOFFQ + NTOOBS(IMNSM)**2*NTOOBS(IPQSM)*NACOBS(IPQSM)
         IOFFF = IOFFF  
     &         + NTOOBS(IMNSM)*(NTOOBS(IMNSM)+1)/2
     &         * (NTOOBS(IPQSM)-1)*(NTOOBS(IPQSM)-2)/2
        END DO
      END DO ! Loops over IMNSM, IPQSM
*
      IF(NTEST.GE.1000) THEN
        WRITE(6,*) ' The F2-matrix as delivered '
        WRITE(6,*) ' ========================== '
        IOFF = 1
        DO IMNSM = 1, NSMOB 
         DO IPQSM = 1, NSMOB
          NMN = NTOOBS(IMNSM)*(NTOOBS(IMNSM)-1)/2
          NPQ = (NTOOBS(IPQSM)-1)*(NTOOBS(IPQSM)-2)/2
          WRITE(6,'(A,2I3)') ' Block with MNSM, PQSM = ',
     &    IMNSM,IPQSM
          CALL WRTMAT(F2,NMN,NPQ,NMN,NPQ)
          IOFF = IOFF + NMN*NPQ
         END DO
        END DO
      END IF
*

      CALL QEXIT('F2MAT')
      CALL MEMMAN(IDUM,IDUM,'FLUSM ',IDUM,'F2MAT ')
*
      RETURN
      END
      SUBROUTINE GET_QMAT(QM,IQ_OFF)
*
* Obtain Q-matrix: Q(m,n,p,q) = \sum_w ((mn!pq) - (mw!pn)) D(qw)
* First two indeces are required to have identical symmetry- as are the last two
* Note that the last index is active
*
* Jeppe Olsen, Aug. 23, 2012, Minneapolis
* Last revision, Aug. 23 - 2012, Jeppe Olsen
*
*. Initial version - celebrating the extreme power of current computers
*                    (positive spin on the expression: a very sloppy and inefficient initial code)
*
*
      INCLUDE 'implicit.inc'
      INTEGER P,Q,W,PT,QT,WT,PQ
      INCLUDE 'mxpdim.inc'
      INCLUDE 'wrkspc-static.inc'
      INCLUDE 'orbinp.inc'
      INCLUDE 'spinfo.inc'
      INCLUDE 'lucinp.inc'
      INCLUDE 'glbbas.inc'
*. Output
      DIMENSION QM(*)
      INTEGER IQ_OFF(NSMOB,NSMOB)
*
      IDUM = 1
      CALL MEMMAN(IDUM,IDUM,'MARK ',IDUM,'QMAT ')
      NAA = NACOB**2
      CALL MEMMAN(KLRHO1,NAA,'ADDL  ',2,'RHO1_S')
      CALL MEMMAN(KLVEC,NACOB,'ADDL  ',2,'VEC_AC')
      CALL MEMMAN(KLVEC2,NACOB,'ADDL  ',2,'VEC_A2')
*
* =======
* Offsets
* =======
*
      IOFF = 1
      DO IMNSM = 1, NSMOB
       DO IPQSM = 1, NSMOB
         IQ_OFF(IMNSM,IPQSM) = IOFF
         NELMNT = 
     &   NTOOBS(IMNSM)*NTOOBS(IMNSM)*NTOOBS(IPQSM)*NACOBS(IPQSM)
         IOFF = IOFF + NELMNT
       END DO
      END DO
*
*======================================
* Reform Rho1 to Symmetry-blocked form
*======================================
*

C     REFORM_RHO1_TO_GNSM(RHO1_ST,RHO1_GNSM_ST,IWAY,IREO_GNSYM_TO_TS)
      CALL REFORM_RHO1_TO_GNSM(WORK(KRHO1),WORK(KLRHO1),1,
     &                         WORK(KIREO_GNSYM_TO_TS_ACOB))
*
* ===================
* And then the matrix 
* ===================
*
      DO IMNSM = 1, NSMOB
       DO IPQSM = 1, NSMOB
        IOFF = IQ_OFF(IMNSM,IPQSM)
        NTMN = NTOOBS(IMNSM)
        NTPQ = NTOOBS(IPQSM)
        NAPQ = NACOBS(IPQSM)
        DO M = 1, NTMN
        DO N = 1, NTMN
        DO P = 1, NTPQ
         MT = IREOST(M)
         NT = IREOST(N)
         PT = IREOST(P)
*. Collect integrals vec(w) = (mn!pw) - (mw!pn)
         DO W = 1, NAPQ
          WT = IREOST(W)
          WORK(KLVEC-1+W) = 
     &    GTIJKL_GN(MT,NT,PT,WT)-GTIJKL_GN(MT,QT,PT,NT)
         END DO
         IOFF_R1 = 1
         DO ISM = 1, IPQSM-1
           IOFF_R1 = IOFF_R1 + NACOBS(ISM)**2
         END DO
         CALL MATVCB(WORK(KLRHO1-1+IOFF_R1),WORK(KLVEC),WORK(KLVEC2),
     &        NAPQ,NAPQ,0)
         MN = (N-1)*NTMN + M
         DO Q = 1, NAPQ
           PQ = (Q-1)*NTPQ + P
           MNPQ = (PQ-1)*NTMN*NTMN+PQ
           QM(IOFF-1+MNPQ) = WORK(KLVEC2-1+Q)
         END DO! End of loop over Q
        END DO
        END DO
        END DO ! End of loops over M,N,P
       END DO ! Loop over IPQSM
      END DO ! Loop over IMNSM
*
      NTEST = 1000
      IF(NTEST.GE.1000) THEN
        WRITE(6,*)
        WRITE(6,*) ' ============='
        WRITE(6,*) ' The Q-matrix '
        WRITE(6,*) ' ============='
        WRITE(6,*) 
        DO IMNSM = 1, NSMOB
          DO IPQSM = 1, NSMOB
            WRITE(6,'(A,2I3)') 
     &      ' Block with IMNSM, IPQSM = ', IMNSM,IPQSM
            IOFF = IQ_OFF(IMNSM,IPQSM)
            NMN = NTOOBS(IMNSM)**2
            NPQ = NTOOBS(IPQSM)*NACOBS(IPQSM)
            CALL  WRTMAT(QM(IOFF),NMN,NPQ,NMN,NPQ)
          END DO
        END DO
      END IF
*
      CALL MEMMAN(IDUM,IDUM,'FLUSM',IDUM,'QMAT ')
*
      RETURN
      END
      SUBROUTINE GET_CE_BLOCKS_OF_F2(NCEXC,ICEXC,NEEXC,IEEXC, 
     &           F2,F2CC,F2CE,F2EC,F2EE,IF2_OFF)
*
* Obtain C and E blocks of F from the complete F-matrix
*
*. Jeppe Olsen, Aug. 23 - 2012, Minneapolis
*  Last revision, Aug. 23 2012, Jeppe Olsen
*
      INCLUDE 'implicit.inc'
      INTEGER P,Q,PS,QS, PS_REL, QS_REL, PQ
      INCLUDE 'mxpdim.inc'
      INCLUDE 'orbinp.inc'
      INCLUDE 'lucinp.inc'
*. Input
      DIMENSION F2(*), IF2_OFF(NSMOB,NSMOB)
      INTEGER ICEXC(2,NCEXC),IEEXC(2,NEEXC)
*. Output
      DIMENSION F2CC(NCEXC*NCEXC),F2CE(NCEXC*NEEXC) 
      DIMENSION F2EE(NEEXC*NEEXC),F2EC(NEEXC*NCEXC)
*
      NTEST = 1000
*
*=====
*F2CC
*=====
*
      DO IMN_EXC = 1, NCEXC
      DO IPQ_EXC = 1, NCEXC
*
        M = ICEXC(1,IMN_EXC)
        N = ICEXC(2,IMN_EXC)
        P = ICEXC(1,IPQ_EXC)
        Q = ICEXC(2,IPQ_EXC)
*
        MS = IREOTS(M)
        NS = IREOTS(N)
        PS = IREOTS(P)
        QS = IREOTS(Q)
*
        IMNSM = ISMFSO(MS)
        IPQSM = ISMFSO(PS)
        NMN = NTOOBS(IMNSM)
        NMNMN = NMN*(NMN+1)/2
*
        MS_REL = MS - IBSO(IMNSM)+1
        NS_REL = NS - IBSO(IMNSM)+1
        PS_REL = PS - IBSO(IPQSM)+1
        QS_REL = QS - IBSO(IPQSM)+1
*
        MN = MS_REL*(MS_REL-1)/2 + NS_REL
        PQ = (PS_REL-1)*(PS_REL-2)/2 + QS_REL
        MNPQ = (PQ-1)*NMNMN + MN
*
        MNPQ_UT = (IMN_EXC-1)*NCEXC + IPQ_EXC
        F2CC(MNPQ_UT) = F2(IF2_OFF(IMNSM,IPQSM)-1+MNPQ)
      END DO
      END DO
*=====
*F2CE
*=====
*
      DO IMN_EXC = 1, NCEXC
      DO IPQ_EXC = 1, NEEXC
*
        M = ICEXC(1,IMN_EXC)
        N = ICEXC(2,IMN_EXC)
        P = IEEXC(1,IPQ_EXC)
        Q = IEEXC(2,IPQ_EXC)
*
        MS = IREOTS(M)
        NS = IREOTS(N)
        PS = IREOTS(P)
        QS = IREOTS(Q)
*
        IMNSM = ISMFSO(MS)
        IPQSM = ISMFSO(PS)
        NMN = NTOOBS(IMNSM)
        NMNMN = NMN*(NMN+1)/2
*
        MS_REL = MS - IBSO(IMNSM)+1
        NS_REL = NS - IBSO(IMNSM)+1
        PS_REL = PS - IBSO(IPQSM)+1
        QS_REL = QS - IBSO(IPQSM)+1
*
        MN = MS_REL*(MS_REL-1)/2 + NS_REL
        PQ = (PS_REL-1)*(PS_REL-2)/2 + QS_REL
        MNPQ = (PQ-1)*NMNMN + PQ
*
        MNPQ_UT = (IMN_EXC-1)*NCEXC + IPQ_EXC
        F2CE(MNPQ_UT) = F2(IF2_OFF(IMNSM,IPQSM)-1+MNPQ)
      END DO
      END DO
*
*=====
*F2EC
*=====
*
      DO IMN_EXC = 1, NEEXC
      DO IPQ_EXC = 1, NCEXC
*
        M = IEEXC(1,IMN_EXC)
        N = IEEXC(2,IMN_EXC)
        P = ICEXC(1,IPQ_EXC)
        Q = ICEXC(2,IPQ_EXC)
*
        MS = IREOTS(M)
        NS = IREOTS(N)
        PS = IREOTS(P)
        QS = IREOTS(Q)
*
        IMNSM = ISMFSO(MS)
        IPQSM = ISMFSO(PS)
        NMN = NTOOBS(IMNSM)
        NMNMN = NMN*(NMN+1)/2
*
        MS_REL = MS - IBSO(IMNSM)+1
        NS_REL = NS - IBSO(IMNSM)+1
        PS_REL = PS - IBSO(IPQSM)+1
        QS_REL = QS - IBSO(IPQSM)+1
*
        MN = MS_REL*(MS_REL-1)/2 + NS_REL
        PQ = (PS_REL-1)*(PS_REL-2)/2 + QS_REL
        MNPQ = (PQ-1)*NMNMN + PQ
*
        MNPQ_UT = (IMN_EXC-1)*NEEXC + IPQ_EXC
        F2EC(MNPQ_UT) = F2(IF2_OFF(IMNSM,IPQSM)-1+MNPQ)
      END DO
      END DO
*
*=====
*F2EE
*=====
*
      DO IMN_EXC = 1, NEEXC
      DO IPQ_EXC = 1, NEEXC
*
        M = IEEXC(1,IMN_EXC)
        N = IEEXC(2,IMN_EXC)
        P = IEEXC(1,IPQ_EXC)
        Q = IEEXC(2,IPQ_EXC)
*
        MS = IREOTS(M)
        NS = IREOTS(N)
        PS = IREOTS(P)
        QS = IREOTS(Q)
*
        IMNSM = ISMFSO(MS)
        IPQSM = ISMFSO(PS)
        NMN = NTOOBS(IMNSM)
        NMNMN = NMN*(NMN+1)/2
*
        MS_REL = MS - IBSO(IMNSM)+1
        NS_REL = NS - IBSO(IMNSM)+1
        PS_REL = PS - IBSO(IPQSM)+1
        QS_REL = QS - IBSO(IPQSM)+1
*
        MN = MS_REL*(MS_REL-1)/2 + NS_REL
        PQ = (PS_REL-1)*(PS_REL-2)/2 + QS_REL
        MNPQ = (PQ-1)*NMNMN + PQ
*
        MNPQ_UT = (IMN_EXC-1)*NEEXC + IPQ_EXC
        F2EE(MNPQ_UT) = F2(IF2_OFF(IMNSM,IPQSM)-1+MNPQ)
      END DO
      END DO
*
      IF(NTEST.GE.1000) THEN
        WRITE(6,*)
        WRITE(6,*) ' Output from GET_CE_BLOCKS_OF_F2 '
        WRITE(6,*) ' ================================'
        WRITE(6,*) 
        WRITE(6,*) ' F2CC: '
        CALL WRTMAT(F2CC,NCEXC,NCEXC,NCEXC,NCEXC)
        WRITE(6,*) ' F2CE: '
        CALL WRTMAT(F2CC,NCEXC,NEEXC,NCEXC,NEEXC)
        WRITE(6,*) ' F2EC '
        CALL WRTMAT(F2CC,NEEXC,NCEXC,NEEXC,NCEXC)
        WRITE(6,*) ' F2EE '
        CALL WRTMAT(F2CC,NEEXC,NEEXC,NEEXC,NEEXC)
      END IF
*
      RETURN
      END
      SUBROUTINE GET_E1_E2_EFF(E1C,E1E,E2CC,E2EE,E2CE,E2EC,NC,NE,
     &           F2CC,F2CE,E1EFF, E2EFF)
*
* Generate the effective gradient and Hessian for the AKBK optimization
*
*. Jeppe Olsen, Aug. 24 - 2012, Minneapolis
*. Last revision, Aug. 24 2012, Jeppe Olsen
*
*. E1EFF = E1E - F2CE T * F2CC (T) ** -1 E1C
*. E2EFF = E2EE - F2CC (T) ** -1 E2CE
*.              - E2EC*F2CC ** -1 F2CE
*.              + F2CC (T) ** -1 E2CC F2CC ** -1 F2CE
*
      INCLUDE 'implicit.inc'
      INCLUDE 'mxpdim.inc'
      INCLUDE 'wrkspc-static.inc'
*. Input
      DIMENSION E1C(NC),E1E(NE)
      DIMENSION E2CC(NC,NC),E2CE(NC,NE),E2EC(NE,NC),E2EE(NE,NE)
*
      NTEST = 1000
      IF(NTEST.GE.100) THEN
        WRITE(6,*) ' GET_E1_E2_EFF speaking '
        WRITE(6,*) ' ====================== '
      END IF
*
      IDUM = 0
      CALL MEMMAN(IDUM,IDUM,'MARK  ',IDUM,'GT_EEF')
*
*. 1 Obtain F2CC ** -1 
*
      NMAX = MAX(NC,NE)
      CALL MEMMAN(KLF2CCI,NMAX**2,'ADDL  ',2,'F2CCI ')
      CALL MEMMAN(KLF2CP,NMAX**2,'ADDL  ',2,'F2CCCP')
      CALL MEMMAN(KLF2CPB,NMAX**2,'ADDL  ',2,'F2CCCB')
      CALL MEMMAN(KLCVEC,NMAX,'ADDL  ',2,'CVEC  ')
*
C     INVMAT(A,B,MATDIM,NDIM,ISING)
      CALL COPVEC(F2CC, WORK(KLF2CP),NC**2)
      CALL INVMAT(WORK(KLF2CP),WORK(KLF2CCI),NC,NC,ISING)
      IF(ISING.NE.0) THEN
        WRITE(6,*) ' Warning: problems with inversion of E2CC '
        WRITE(6,*) ' However, I am in a optimistic mood and continue'
      END IF
*
* 2: E1EFF = E1E - F2CE T * F2CC (T) ** -1 E1C
*
C MATVCC(A,VIN,VOUT,NROW,NCOL,ITRNS)
      CALL MATVCC(WORK(KLF2CCI),E1C,WORK(KLCVEC),NC,NC,1)
      CALL MATVCC(F2CE,WORK(KLCVEC),E1EFF,NC,NE,1)
      ONEM = -1.0D0
      ONE  = 1.0D0
      CALL VECSUM(E1EFF,E1EFF,E1E,ONEM,ONE,NC)
*
* 3 : E2EFF = E2EE -F2CE T F2CC (T) ** -1 E2CE
*.          - E2EC*F2CC ** -1 F2CE
*.          + F2CE(T) F2CC (T) ** -1 E2CC F2CC ** -1 F2CE
*
* a) E2EE - F2CE T F2CC (T) ** -1 E2CE
*
      CALL COPVEC(E2EE,E2EFF,NE**2)
      FACTORC = 0.0D0
      FACTORAB = 1.0D0
      CALL MATML7(WORK(KLF2CP), WORK(KLF2CCI),E2CE,
     &     NC,NE,NC,NC,NC,NE,FACTORC,FACTORAB,1)
      FACTORC = 1.0D0
      FACTORAB = -1.0D0
      CALL MATML7(E2EFF,F2CE,WORK(KLF2CP),
     &            NE,NE,NC,NE,NC,NE,
     &            FACTORC,FACTORAB,1)
*
* b) - E2EC*F2CC ** -1 F2CE
*
      FACTORC = 0.0D0
      FACTORAB = 1.0D0
      CALL MATML7(WORK(KLF2CP),E2EC, WORK(KLF2CCI),
     &     NC,NE,NC,NC,NC,NE,FACTORC,FACTORAB,0)
      FACTORC = 1.0D0
      FACTORAB = -1.0D0
      CALL MATML7(E2EFF,WORK(KLF2CP),F2CE,
     &     NE,NE,NE,NC,NC,NE,FACTORC,FACTORAB,0)
*
* c)  + F2CE(T) F2CC (T) ** -1 E2CC F2CC ** -1 F2CE
*
      FACTORC = 0.0D0
      FACTORAB = 1.0D0
      CALL MATML7(WORK(KLF2CP),WORK(KLF2CCI),F2CE,
     &     NC,NE,NC,NC,NC,NE,FACTORC,FACTORAB,0)
      FACTORC = 0.0D0
      FACTORAB = 1.0D0
      CALL MATML7(WORK(KLF2CPB),E2CC,WORK(KLF2CP),
     &     NC,NE,NC,NC,NC,NE,FACTORC,FACTORAB,0)
      FACTORC = 0.0D0
      FACTORAB = 1.0D0
      CALL MATML7(WORK(KLF2CP),WORK(KLF2CCI),WORK(KLF2CPB),
     &     NC,NE,NC,NC,NC,NE,FACTORC,FACTORAB,1)
      FACTORC = 1.0D0
      FACTORAB = 1.0D0
      CALL MATML7(E2EFF,F2CE,WORK(KLF2CP),
     &     NE,NE,NC,NE,NC,NE,FACTORC,FACTORAB,1)
*
      IF(NTEST.GE.1000) THEN
       WRITE(6,*) ' Effective gradient'
       CALL WRTMAT(E1EFF,NE,1,NE,1)
       WRITE(6,*)
       WRITE(6,*) ' Effective Hessian '
       CALL WRTMAT(E2EFF,NE,NE,NE,NE)
      END IF
*
      CALL MEMMAN(IDUM,IDUM,'FLUSM ',IDUM,'GT_EEF')
      RETURN
      END
      SUBROUTINE LUCIA_AKMCSCF(IREFSM,IREFSPC_MCSCF,MAXMAC,MAXMIC,
     &                       EFINAL,CONVER,VNFINAL)
*
* Master routine for MCSCF optimization within the AK approximation
*
* Jeppe Olsen, Aug 24, 2012, Minneapolis
* Last revision, Aug. 23 2012, Jeppe Olsen

* Initial MO-INI transformation matrix is assumed set outside and is in MOMO
* Initial MO-AO transformation matrix is in MOAOIN
*
*. Output matrix is in
*   1) MOAOUT   - as it is the output matrix
*   2) MOAO_ACT - as it is the active matrix
*   3) MOAOIN   - as the integrals are in this basis ...
#include "errquit.fh"
#include "mafdecls.fh"
#include "global.fh"
      INCLUDE 'wrkspc.inc'
      INCLUDE 'glbbas.inc'
      INCLUDE 'cgas.inc'
      INCLUDE 'gasstr.inc'
      INCLUDE 'lucinp.inc'
      INCLUDE 'orbinp.inc'
      INCLUDE 'intform.inc'
      INCLUDE 'cc_exc.inc'
      INCLUDE 'cprnt.inc'
      INCLUDE 'cintfo.inc'
      INCLUDE 'crun.inc'
      INCLUDE 'cecore.inc'
      INCLUDE 'akbk.inc'
      INCLUDE 'spinfo.inc'
*. Some indirect transfer
      COMMON/EXCTRNS/KLOOEXCC,KINT1_INI,KINT2_INI
* A bit of local scratch
      INTEGER ISCR(2), ISCR_NTS((7+MXPR4T)*MXPOBS)
*
      REAL*8
     &INPROD
      LOGICAL DISCH, CONV_INNER
*
      LOGICAL CONV_F,CONVER
      EXTERNAL EMCSCF_FROM_KAPPA
* Removing (incorrect) compiler warnings
      KINT2_FSAVE = 0
      IE2ARR_F = -1

      IDUMMY = 0
      CALL MEMMAN(IDUMMY, IDUMMY, 'MARK ', IDUMMY,'AKMCSC') 
      CALL QENTER('AKMCS')
*
*. Local parameters defining optimization
*
*. reset kappa to zero in each inner or outer iteration
*
* IRESET_KAPPA_IN_OR_OUT = 1 => Reset kappa in each inner iteration
* IRESET_KAPPA_IN_OR_OUT = 2 => Reset kappa in each outer iteration
*
*. Use gradient or Brillouin vector (differs only when gradient is 
*  evaluated for Kappa ne. 0, ie. IRESET_KAPPA = 2
*
* I_USE_BR_OR_E1 = 1 => Use Brilloin vector
* I_USE_BR_OR_E2 = 2 => Use E1
      IRESET_KAPPA_IN_OR_OUT = 2
      I_USE_BR_OR_E1 = 2 
*. Largest allowed number of vectors in update
      NMAX_VEC_UPDATE = 50
*. Restrict orbital excitations in case of super-symmetry
      INCLUDE_ONLY_TOTSYM_SUPSYM = 1
*
      WRITE(6,*) ' *****************************************'
      WRITE(6,*) ' *                                       *'
      WRITE(6,*) ' * AK MCSCF optimization control entered *'
      WRITE(6,*) ' *                                       *'
      WRITE(6,*) ' * Version -1, Jeppe Olsen, August 12    *'
      WRITE(6,*) ' *****************************************'
      WRITE(6,*)
      WRITE(6,*) ' Occupation space: ', IREFSPC_MCSCF
      WRITE(6,*) ' Allowed number of outer iterations ', MAXMAC
      WRITE(6,*) ' Allowed number of inner iterations ', MAXMIC
*
* Some temporary(?) parameters to define transition from standard 
* to AK optimization
*
      I_DO_APPROX_DENS = 1
      I_DO_APPROX_CI = 1
      I_DO_CONSTR = 1
      WRITE(6,*) ' Temporary parameters: '
      WRITE(6,'(A,3I3)') 
     &'I_DO_APPROX_DENS, I_DO_APPROX_CI,I_DO_CONSTR ',
     & I_DO_APPROX_DENS, I_DO_APPROX_CI,I_DO_CONSTR   
*
      IF(I_USE_SUPSYM.EQ.1) THEN
        IF(INCLUDE_ONLY_TOTSYM_SUPSYM.EQ.1) THEN
          WRITE(6,*) 
     &   ' Excitations only between orbs with the same supersymmetry'
        ELSE
          WRITE(6,'(2X,A)') 
     &   'Excitations only between orbs with the same standard symmetry'
        END IF
      END IF
*
      WRITE(6,*)
      WRITE(6,*) ' MCSCF optimization method in action:'
      IF(IMCSCF_MET.EQ.1) THEN
        WRITE(6,*) '    One-step method NEWTON'
      ELSE  IF (IMCSCF_MET.EQ.2) THEN
        WRITE(6,*) '    Two-step method NEWTON'
      ELSE  IF (IMCSCF_MET.EQ.3) THEN
        WRITE(6,*) '    One-step method Update'
      ELSE  IF (IMCSCF_MET.EQ.4) THEN
        WRITE(6,*) '    Two-step method Update'
      END IF
*
      IF(IOOE2_APR.EQ.1) THEN
        WRITE(6,*) '    Orbital-Orbital Hessian constructed'
      ELSE IF(IOOE2_APR.EQ.2) THEN
        WRITE(6,*) 
     &  '    Diagonal blocks of Orbital-Orbital Hessian constructed'
      ELSE IF(IOOE2_APR.EQ.3) THEN
        WRITE(6,*) 
     &  '    Approx. diagonal of Orbital-Orbital Hessian constructed'
      END IF
*
*. Linesearch
*
      IF(IMCSCF_MET.LE.2) THEN
       IF(I_DO_LINSEA_MCSCF.EQ.1) THEN 
         WRITE(6,*) 
     &   '    Line search for Orbital optimization '
       ELSE IF(I_DO_LINSEA_MCSCF.EQ.0) THEN
         WRITE(6,*) 
     &   '    Line search when energy increases '
       ELSE IF(I_DO_LINSEA_MCSCF.EQ.-1) THEN
         WRITE(6,*) 
     &   '    Line search never carried out '
       END IF
      ELSE
*. Update method linesearch always used
        WRITE(6,*) 
     &  '    Line search for Orbital optimization '
      END IF
      IF(IMCSCF_MET.EQ.3.OR.IMCSCF_MET.EQ.4) THEN
        WRITE(6,'(A,I4)') 
     &  '     Max number of vectors in update space ', NMAX_VEC_UPDATE
      END IF
*
      IF(IRESET_KAPPA_IN_OR_OUT .EQ.1 ) THEN
        WRITE(6,*) 
     &  '       Kappa is reset to zero in each inner iteration '
      ELSE IF( IRESET_KAPPA_IN_OR_OUT .EQ.2 ) THEN
        WRITE(6,*) ' Kappa is reset to zero in each outer iteration '
      END IF
*
      IF(I_USE_BR_OR_E1.EQ.1) THEN
        WRITE(6,*) '    Brillouin vector in use'
      ELSE IF(I_USE_BR_OR_E1 .EQ.2) THEN
        WRITE(6,*) '    Gradient vector in use'
      END IF
*
      IF(NFRZ_ORB.NE.0) THEN
        WRITE(6,*) ' Orbitals frozen in MCSCF optimization: '
        CALL IWRTMA3(IFRZ_ORB,1,NFRZ_ORB,1,NFRZ_ORB)
      END IF
      
      I_MAY_DO_CI_IN_INNER_ITS = 0
      XKAPPA_THRES = 0.0D0
      MIN_OUT_IT_WITH_CI = 10
      IF(IMCSCF_MET.EQ.3) THEN
        I_MAY_DO_CI_IN_INNER_ITS = 1
        XKAPPA_THRES = 1.0D-1
        WRITE(6,'(A)') 
     &  '     CI - optimization in inner iterations starts when: '
        WRITE(6,'(A)')
     &  '       Hessian approximation is not shifted'
        WRITE(6,'(A,E8.2)') 
     &  '       Initial step is below ',  XKAPPA_THRES
        WRITE(6,'(A,I3)') 
     &  '     Outer iteration is atleast number ', MIN_OUT_IT_WITH_CI
      END IF
*
*. Initial allowed step length 
      STEP_MAX = 0.75D0
C     WRITE(6,*) ' Jeppe has reduced step to ', STEP_MAX
      TOLER = 1.1D0
      NTEST = 1000
      IPRNT= MAX(NTEST,IPRMCSCF)
*
      I_DO_NEWTON = 0
      I_DO_UPDATE = 0
      I_UPDATE_MET = 0
      IF(IMCSCF_MET.LE.2) THEN
        I_DO_NEWTON = 1
      ELSE IF (IMCSCF_MET.EQ.3.OR.IMCSCF_MET.EQ.4) THEN
        I_DO_UPDATE = 1
*. use BFGS update
        I_UPDATE_MET = 2
*. Update vectors will be kept in core
        DISCH = .FALSE.
        LUHFIL = -2810
      END IF
      WRITE(6,*) ' I_DO_NEWTON, I_DO_UPDATE = ', 
     &             I_DO_NEWTON, I_DO_UPDATE
*
*. Memory for information on convergence of iterative procedure
      NITEM = 4
      LEN_SUMMARY = NITEM*(MAXMAC+1)
      CALL MEMMAN(KL_SUMMARY,LEN_SUMMARY,'ADDL  ',2,'SUMMRY')
*. Memory for the initial set of MO integrals
      CALL MEMMAN(KINT1_INI,NINT1,'ADDL  ',2,'INT1_IN')
      CALL MEMMAN(KINT2_INI,NINT2,'ADDL  ',2,'INT2_IN')
*. And for two extra MO matrices 
      LEN_CMO =  NDIM_1EL_MAT(1,NTOOBS,NTOOBS,NSMOB,0)
      CALL MEMMAN(KLMO1,LEN_CMO,'ADDL  ',2,'MO1   ')
      CALL MEMMAN(KLMO2,LEN_CMO,'ADDL  ',2,'MO2   ')
      CALL MEMMAN(KLMO3,LEN_CMO,'ADDL  ',2,'MO3   ')
      CALL MEMMAN(KLMO4,LEN_CMO,'ADDL  ',2,'MO4   ')
*. And for storing MO coefficients from outer iteration
      CALL MEMMAN(KLMO_OUTER,LEN_CMO,'ADDL  ',2,'MOOUTE')
*. And initial set of MO's
      CALL MEMMAN(KLCMOAO_INI,LEN_CMO,'ADDL  ',2,'MOINI ')
*. Normal integrals accessed
      IH1FORM = 1
      I_RES_AB = 0
      IH2FORM = 1
*. CI not CC
      ICC_EXC = 0
*. Use of supersymmetry in generation of excitations?
      IF(I_USE_SUPSYM.EQ.1.AND.INCLUDE_ONLY_TOTSYM_SUPSYM.EQ.1) THEN
        I_RESTRICT_SUPSYM = 1
      ELSE 
        I_RESTRICT_SUPSYM = 0
      END IF
*
* ============================================
* Initialize info for Dual space (PQ ) set up
* ============================================
*
*. Code requires use of CSFS and ICNFBAT = 2, Check
*
* Test that CSFs are in use
      IF(NOCSF.EQ.1) THEN
        WRITE(6,*) ' AKBK calculation with determinants is not enabled'
        WRITE(6,*) ' Please remove NOCSF keyword '
        STOP       ' AKBK calculation with determinants is not enabled'
      END IF
      IF(ICNFBAT.EQ.1.OR.ICISTR.EQ.1) THEN
        WRITE(6,*) ' AKBK calculation does not work with incore options'
        WRITE(6,*) ' Please make sure ICNFBAT .ge. 2 and ICISTR .ge. 2 '
        STOP       ' AKBK calculation does not work with incore options'
      END IF
*
      IPSPC = IREFSPC_MCSCF-1
      IQSPC = IREFSPC_MCSCF
      WRITE(6,*) ' IPSPC, IQSPC = ', IPSPC, IQSPC
     
*. Number of CSFs in P and Q
      NPCSF = NCSF_PER_SYM_GN(IREFSM,IPSPC)
      NQCSF = NCSF_PER_SYM_GN(IREFSM,IQSPC)
      IF(NTEST.GE.10) THEN
        WRITE(6,*) ' Number of CSFs in P-space = ', NPCSF
        WRITE(6,*) ' Number of CSFs in PQ-space = ', NQCSF
      END IF
      EREF_INI = EREF
*
*=====================================
* Construction of orbital excitations 
*=====================================
*
* In the present context, we will have two sets of orbital excitations.
*   The standard orbital excitations (interspace), named e
*   The extra rotations connected with constraints (intraspace) named d
*
* We will need to work with thise together and alone. This is 
* realized by ordering the excitations so
*  1) The e-excitations come first
*  2) The c-excitations then show up
*
*
*. The number of e-excitations
      CALL MEMMAN(KLTTACT,(NGAS+2)**2,'ADDL  ',1,'TTACT ')
      CALL NONRED_TT_EXC(WORK(KLTTACT),IREFSPC_MCSCF,1)
*. Number of Nonredundant orbital excitations
      KLOOEXC = 1
      KLOOEXCC= 1
      CALL NONRED_OO_EXC2(NOOEXC,WORK(KLOOEXC),WORK(KLOOEXCC),
     &     1,WORK(KLTTACT),I_RESTRICT_SUPSYM,WORK(KMO_SUPSYM),
     &     N_INTER_EXC,N_INTRA_EXC,1)
      NEOOEXC = N_INTER_EXC
      NCOOEXC = N_INTRA_EXC
*
      IF(NOOEXC.EQ.0) THEN
        WRITE(6,*) ' STOP: zero orbital excitations in MCSCF '
        STOP       ' STOP: zero orbital excitations in MCSCF '
      END IF
*.. And the excitations
      CALL MEMMAN(KLOOEXC,NTOOB*NTOOB,'ADDL  ',1,'OOEXC ')
      CALL MEMMAN(KLOOEXCC,2*NOOEXC,'ADDL  ',1,'OOEXCC')
*. Allow these parameters to be known outside
      KIOOEXC = KLOOEXC
      KIOOEXCC = KLOOEXCC
      CALL NONRED_OO_EXC2(NOOEXC,WORK(KLOOEXC),WORK(KLOOEXCC),
     &     1,WORK(KLTTACT),I_RESTRICT_SUPSYM,WORK(KMO_SUPSYM),
     &     N_INTER_EXC,N_INTRA_EXC,2)
*
* =========================================================================
* Memory allocation - why now: We needed to know the number of excitations
* =========================================================================
*
*. Memory for gradient 
      CALL MEMMAN(KLE1,NOOEXC,'ADDL  ',2,'E1_MC ')
*. And Brillouin matrix in complete form
      CALL MEMMAN(KLBR,LEN_CMO,'ADDL  ',2,'BR_MAT')
*. And an extra gradient
      CALL MEMMAN(KLE1B,NOOEXC,'ADDL  ',2,'E1B   ')
*. and a scratch vector for excitation
      CALL MEMMAN(KLEXCSCR,NOOEXC,'ADDL  ',2,'EX_SCR')
*. Memory for gradient and orbital-Hessian - if  required
      IF(IOOE2_APR.EQ.1) THEN
        LE2 = NOOEXC*(NOOEXC+1)/2
        CALL MEMMAN(KLE2,LE2,'ADDL  ',2,'E2_MC ')
*. For eigenvectors of orbhessian
        LE2F = NOOEXC**2
        CALL MEMMAN(KLE2F,LE2F,'ADDL  ',2,'E2_MCF')
*. and eigenvalues, scratch, kappa
        CALL MEMMAN(KLE2VL,NOOEXC,'ADDL  ',2,'EIGVAL')
      ELSE
        KLE2 = -1
        KLE2F = -1
        KLE2VL = -1
      END IF
      KLIBENV = -2810
      KCLKSCR = -2810
*
      IF(I_DO_UPDATE.EQ.1) THEN
*. Space for update procedure
*. Array defining envelope and a scratch vector
* and matrix
        CALL MEMMAN(KLIBENV,NOOEXC,'ADDL  ',2,'IBENV')
        CALL MEMMAN(KLCLKSCR,NOOEXC,'ADDL  ',2,'CLKSCR')
*. rank 2 matrices
        CALL MEMMAN(KLRANK2,4*NMAX_VEC_UPDATE,'ADDL  ',2,'RNK2MT')
* two vectors defining each rank two-space
        LENGTH_V = 2*NMAX_VEC_UPDATE*NOOEXC
        CALL MEMMAN(KLUPDVEC,LENGTH_V,'ADDL  ',2,'RNK2VC')
*. Vectors for saving previous kappa and gradient
        CALL MEMMAN(KLE1PREV,NOOEXC,'ADDL  ',2,'E1PREV')
        CALL MEMMAN(KLKPPREV,NOOEXC,'ADDL  ',2,'KPPREV')
      END IF
*. and scratch, kappa
      CALL MEMMAN(KLE2SC,NOOEXC,'ADDL  ',2,'EIGSCR')
      CALL MEMMAN(KLKAPPA,NOOEXC,'ADDL  ',2,'KAPPA ')
      CALL MEMMAN(KLSTEP, NOOEXC,'ADDL  ',2,'STEP  ')
*. Save the initial set of MO integrals 
      CALL COPVEC(WORK(KINT1O),WORK(KINT1_INI),NINT1)
      CALL COPVEC(WORK(KINT2) ,WORK(KINT2_INI),NINT2)
      IF(I_DO_CONSTR.EQ.1) THEN
*. Include space for treating orbital constraints: For the F2 matrix
*. and partitionings of F2, E2, and E1.
        LFE2 = (NOOEXC+NTOOB)*NOOEXC
        CALL MEMMAN(KLFE2,LFE2,'ADDL  ',2,'FE2   ')
        LCC = NCOOEXC*NCOOEXC
        LCE = NCOOEXC*NEOOEXC
        LEE = NEOOEXC*NEOOEXC
        CALL MEMMAN(KLFE2CC,LCC,'ADDL  ',2,'FE2CC ')
        CALL MEMMAN(KLFE2CE,LCE,'ADDL  ',2,'FE2CC ')
        CALL MEMMAN(KLFE2EC,LCE,'ADDL  ',2,'FE2CC ')
        CALL MEMMAN(KLFE2EE,LEE,'ADDL  ',2,'FE2CC ')
        CALL MEMMAN(KLE2CC,LCC,'ADDL  ',2,'E2CC  ')
        CALL MEMMAN(KLE2CE,LCE,'ADDL  ',2,'E2CC  ')
        CALL MEMMAN(KLE2EC,LCE,'ADDL  ',2,'E2CC  ')
        CALL MEMMAN(KLE2EE,LEE,'ADDL  ',2,'E2CC  ')
        CALL MEMMAN(KLE1C,NCOOEXC,'ADDL  ',2,'E1C   ')
        CALL MEMMAN(KLE1E,NEOOEXC,'ADDL  ',2,'E1E   ')
        LEN_H1 =  NDIM_1EL_MAT(1,NTOOBS,NTOOBS,NSMOB,1)
        CALL MEMMAN(KLFIA,LENH1,'ADDL  ',2,'FIA    ')
        CALL MEMMAN(KLF2OFF,NSMOB**2,'ADDL  ',1,'F2OFF ')
      END IF
*. Print will be reduced for densities
      IPRDEN_SAVE = IPRDEN
C     IPRDEN = 0
      IRESTR_SAVE = IRESTR
*
      IIUSEH0P = 0
      MPORENP_E = 0
      IPRDIAL = IPRMCSCF
*
      CONVER = .FALSE.
      CONV_F = .FALSE.
*. The various types of integral lists- should probably be made in
* def of lists
      IE2LIST_0F = 1
      IE2LIST_1F = 2
      IE2LIST_2F = 3
      IE2LIST_4F = 5
*. For integral transformation: location of MO coefs
      KKCMO_I = KMOMO
      KKCMO_J = KMOMO
      KKCMO_K = KMOMO
      KKCMO_L = KMOMO
*
      IF(I_DO_UPDATE.EQ.1) THEN
*. Define envelope for used orbital Hessian - pt complete
* is constructed so
        IONE = 1
        CALL ISETVC(WORK(KLIBENV),IONE,NOOEXC)
      END IF
*
*. Loop over outer iterations
*
* In summery
* 1: Norm of orbgradient
* 2: Norm of orbstep
* 3: Norm of CI after iterative procedure
* 4: Energy
*
*. Convergence is pt  energy change le THRES_E
*
      ZERO = 0.0D0
      NMAT_UPD = 0
*. Line search is not meaning full very close to convergence
      THRES_FOR_ENTER_LINSEA = 1.0D-8

      N_INNER_TOT = 0
      DO IOUT = 1, MAXMAC
*
        IF(IPRNT.GE.1) THEN
          WRITE(6,*)
          WRITE(6,*) ' ----------------------------------'
          WRITE(6,*) ' Output from outer iteration', IOUT
          WRITE(6,*) ' ----------------------------------'
          WRITE(6,*)
        END IF
        CALL MEMCHK2('ST_OUT')
        NOUTIT = IOUT
*
*. Transform integrals to current set of MO's
*
        IF(IPRNT.GE.10) WRITE(6,*) ' Integral transformation:' 
        KINT2 = KINT_2EMO
        CALL COPVEC(WORK(KINT1_INI),WORK(KINT1O),NINT1)
        CALL COPVEC(WORK(KINT2_INI),WORK(KINT2),NINT2)
*. Flag type of integral list to be obtained
C       IE2LIST_A, IOCOBTP_A,INTSM_A
*. Flag for integrals with Two  free index: energy + gradient+orb-Hessian
*. Check problem: raise!!
        IE2LIST_A = IE2LIST_2F
        IE2LIST_A = IE2LIST_4F
        IOCOBTP_A = 2
*. Check, end
        INTSM_A = 1
        CALL TRAINT
*
        CALL COPVEC(WORK(KINT1),WORK(KH),NINT1)
*. Calculate inactive Fockmatrix
*. Calculate inactive Fock matrix from integrals over initial orbitals
*
*. A problem with the modern integral structure: the code will look for 
*. a list of full two-electron integrals and will use this, rather than the 
*. above definition. Well, place pointer KINT2_INI at relevant place
        IE2ARR_F = IE2LIST_I(IE2LIST_IB(IE2LIST_FULL))
        KINT2_FSAVE = KINT2_A(IE2ARR_F)
        KINT2_A(IE2ARR_F) = KINT2_INI
C            FI_FROM_INIINT(FI,CINI,H,EINAC,IHOLETP)
        CALL FI_FROM_INIINT(WORK(KFI),WORK(KMOMO),WORK(KH),
     &                      ECORE_HEX,3)
        ECORE = ECORE_ORIG + ECORE_HEX
        CALL COPVEC(WORK(KFI),WORK(KINT1),NINT1)
        IF(NTEST.GE.10000) THEN
          WRITE(6,*) ' MCSCF: ECORE_ORIG, ECORE_HEX, ECORE(2) ',
     &                 ECORE_ORIG, ECORE_HEX, ECORE
        END IF
*. and   redirect integral fetcher back to actual integrals
        KINT2 = KINT_2EMO
        KINT2_A(IE2ARR_F) = KINT2_FSAVE
*. The diagonal will fetch J and K integrals using GTIJKL_GN,* 
*. prepare for this routine
        IE2ARRAY_A = IE2LIST_I(IE2LIST_IB(IE2LIST_A))
*
*. Perform CI - and calculate densities
*
        IF(IPRNT.GE.10) WRITE(6,*) ' CI: '
*. At most MAXMIC iterations
        IF(IOUT.NE.1) IRESTR = 1
     
        MAXIT_SAVE = MAXIT
        IF(I_DO_APPROX_CI.EQ.0) THEN
          CALL GASCI(IREFSM,IREFSPC_MCSCF,IPRDIAL,IIUSEH0P,
     &             MPORENP_E,EREF,ERROR_NORM_FINAL,CONV_F)  
        ELSE
           CALL AKBKCI(IREFSPC_MCSCF,IPRDIAL,
     &           EREF,ERROR_NORM_FINAL,CONV_F)
        END IF
        MAXIT = MAXIT_SAVE
        WRITE(6,*) ' Energy and residual from CI :', 
     &  EREF,ERROR_NORM_FINAL
        WORK(KL_SUMMARY-1+(IOUT-1)*NITEM+3) = ERROR_NORM_FINAL
        WORK(KL_SUMMARY-1+(IOUT-1)*NITEM+4) = EREF
        EOLD = EREF
        ENEW = EREF
*. (Sic)
*
        IF(IOUT.GT.1) THEN
*. Check for convergence
          DELTA_E = WORK(KL_SUMMARY-1+(IOUT-1)*NITEM+4)-
     &              WORK(KL_SUMMARY-1+(IOUT-1-1)*NITEM+4)
          IF(IPRNT.GE.2) WRITE(6,'(A,E9.3)') 
     &    '  Change of energy between outer iterations = ', DELTA_E
          IF(ABS(DELTA_E).LE.THRES_E) CONVER = .TRUE.
        END IF
        IF(CONVER) THEN
          NOUTIT = NOUTIT-1
          IF(IPRNT.GE.1) THEN
            WRITE(6,*) ' MCSCF calculation has converged'
          END IF
          GOTO 1001
        END IF
*. A test
C       CALL EN_FROM_DENS(ENERGY,2,0)
        CALL EN_FROM_DENS(ENERGY2,2,0)
        WRITE(6,*) ' Energy from density matrices ', ENERGY2
*. The active Fock matrix
        IE2ARR_F = IE2LIST_I(IE2LIST_IB(IE2LIST_FULL))
        KINT2_FSAVE = KINT2_A(IE2ARR_F)
        KINT2_A(IE2ARR_F) = KINT2_INI
        CALL FA_FROM_INIINT
     &       (WORK(KFA),WORK(KMOMO),WORK(KMOMO),dbl_mb(KRHO1),1)
*. Clean up
        KINT2 = KINT_2EMO
        KINT2_A(IE2ARR_F) = KINT2_FSAVE
*
*.======================================
*. Exact or approximate orbital Hessian 
*.======================================
*
*
*. Fock matrix in KF
          CALL FOCK_MAT_STANDARD(WORK(KF),2,WORK(KFI),WORK(KFA))
        IOOSM = 1
C            ORBHES(OOHES,IOOEXC,NOOEXC,IOOSM,ITTACT)
        IF(IOOE2_APR.EQ.1) THEN
          CALL ORBHES(WORK(KLE2),WORK(KLOOEXC),NOOEXC,IOOSM,
     &         WORK(KLTTACT))
          IF(NTEST.GE.1000) THEN
           WRITE(6,*) ' The orbital Hessian '
           CALL PRSYM(WORK(KLE2),NOOEXC)
          END IF
        END IF
*
        IF(I_DO_CONSTR.EQ.1) THEN
*. Calculate matrices to ensure that the constraints - FI + FA is 
*. block-diagonal
C     GET_FIA2(F2,FIA,IFIA2_OFFSS)
       END IF
   
*. 
        WRITE(6,*) ' Jeppe enforced me to to stop '
        STOP ' Jeppe enforced me to to stop '
*
*. Diagonalize to determine lowest eigenvalue
*
*. Outpack to complete form
        CALL TRIPAK(WORK(KLE2F),WORK(KLE2),2,NOOEXC,NOOEXC)
C            TRIPAK(AUTPAK,APAK,IWAY,MATDIM,NDIM)
*. Lowest eigenvalue
C            DIAG_SYMMAT_EISPACK(A,EIGVAL,SCRVEC,NDIM,IRETURN)
        CALL DIAG_SYMMAT_EISPACK(WORK(KLE2F),WORK(KLE2VL),
     &       WORK(KLE2SC),NOOEXC,IRETURN)
        IF(IRETURN.NE.0) THEN
           WRITE(6,*) 
     &     ' Problem with diagonalizing E2, IRETURN =  ', IRETURN
        END IF
        IF(IPRNT.GE.1000) THEN
          WRITE(6,*) ' Eigenvalues: '
          CALL WRTMAT(WORK(KLE2VL),1,NOOEXC,1,NOOEXC)
        END IF
*. Lowest eigenvalue
        E2VL_MN = XMNMX(WORK(KLE2VL),NOOEXC,1)
        IF(IPRNT.GE.2)  
     &  WRITE(6,*) ' Lowest eigenvalue of E2(orb) = ', E2VL_MN
*
*. Cholesky factorization orbital Hessian if required
*
        I_SHIFT_E2 = 0
        IF(I_DO_UPDATE.EQ.1) THEN
*. Cholesky factorization requires positive matrices.
*. add a constant to diagonal if needed
          XMINDIAG = 1.0D-4
          IF(E2VL_MN.LE.XMINDIAG) THEN
           ADD = XMINDIAG - E2VL_MN 
C               ADDDIA(A,FACTOR,NDIM,IPACK)
           CALL ADDDIA(WORK(KLE2),ADD,NOOEXC,1)
           I_SHIFT_E2 = 1
          END IF
C CLSKHE(AL,X,B,NDIM,IB,IALOFF,ITASK,INDEF)
C         WRITE(6,*) ' NOOEXC before CLSKHE = ', NOOEXC 
          CALL CLSKHE(WORK(KLE2),XDUM,XDUM,NOOEXC,WORK(KLIBENV),
     &         WORK(KLCLKSCR),1,INDEF)
          IF(INDEF.NE.0) THEN
            WRITE(6,*) ' Indefinite matrix in CKSLHE '
            STOP ' Indefinite matrix in CKSLHE '
          END IF
        END IF! Cholesky decomposition required
*
*
*. Finite difference check
*
        I_DO_FDCHECK = 0
        IF(I_DO_FDCHECK.EQ.1) THEN
*. First: Analytic gradient from Fock matrix - As kappa = 0, Brillouin vector
* = gradient
          CALL E1_FROM_F(WORK(KLE1),WORK(KF),1,WORK(KLOOEXC),
     &                   WORK(KLOOEXCC),
     &                   NOOEXC,NTOOB,NTOOBS,NSMOB,IBSO,IREOST)
*
          CALL MEMMAN(KLE1FD,NOOEXC,'ADDL  ',2,'E1_FD ')
          LE2 = NOOEXC*NOOEXC
          CALL MEMMAN(KLE2FD,LE2,   'ADDL  ',2,'E2_FD ')
          CALL SETVEC(WORK(KLE2VL),ZERO,NOOEXC)
          CALL GENERIC_GRA_HES_FD(E0,WORK(KLE1FD),WORK(KLE2FD),
     &         WORK(KLE2VL),NOOEXC,EMCSCF_FROM_KAPPA)
C              GENERIC_GRA_HES_FD(E0,E1,E2,X,NX,EFUNC)
*. Compare gradients
          ZERO = 0.0D0
          CALL CMP2VC(WORK(KLE1FD),WORK(KLE1),NOOEXC,ZERO)
*. transform Finite difference Hessian to packed form
          CALL TRIPAK(WORK(KLE2FD),WORK(KLE2F),1,NOOEXC,NOOEXC)
          LEN = NOOEXC*(NOOEXC+1)/2
          CALL CMP2VC(WORK(KLE2),WORK(KLE2F),LEN,ZERO)
              STOP ' Enforced stop after FD check'
        END IF
*       ^ End of finite difference check
*. Initialize sum of steps for outer iteration
        WORK(KL_SUMMARY-1+(IOUT-1)*NITEM+2) = 0.0D0
*. Loop over Inner iterations, where orbitals are optimized
*. Initialize Kappa as zero
        IF(IRESET_KAPPA_IN_OR_OUT.EQ.2) THEN
          CALL SETVEC(WORK(KLKAPPA),ZERO,NOOEXC)
        END IF
*. Save MO's from start of each outer iteration
        CALL COPVEC(WORK(KMOMO),WORK(KMOREF),LEN_CMO)
*. Convergence Threshold for inner iterations
*. At the moment just chosen as the total convergence threshold
        THRES_E_INNER = THRES_E
        CONV_INNER = .FALSE.
        DO IINNER = 1, MAXMIC
          N_INNER_TOT = N_INNER_TOT + 1
*
          IF(IPRNT.GE.5) THEN
            WRITE(6,*)
            WRITE(6,*) ' Info from inner iteration = ', IINNER
            WRITE(6,*) ' ===================================='
            WRITE(6,*)
          END IF
*
          IF(IRESET_KAPPA_IN_OR_OUT.EQ.1) THEN
            CALL SETVEC(WORK(KLKAPPA),ZERO,NOOEXC)
          END IF
          E_INNER_OLD = EREF
          EOLD = ENEW
*
          IF(IINNER.NE.1) THEN
*
*. gradient integral transformation and Fock matrices
*
*. Flag type of integral list to be obtained:
*. Flag for integrals with one free index: energy + gradient
           IE2LIST_A = IE2LIST_1F
           IOCOBTP_A = 1
           INTSM_A = 1
           CALL TRAINT
           CALL COPVEC(WORK(KINT1),WORK(KH),NINT1)
*
*. Calculate inactive and active Fock matrix from integrals over 
*  initial orbitals
*. Redirect integral fetcher to initial integrals- for old storage mode
           KINT2 = KINT2_INI
*. A problem with the modern integral structure: the code will look for 
*. a list of full two-electron integrals and will use this, rather than the 
*. above definition. Well, place pointer KINT2_INI at relevant place
           IE2ARR_F = IE2LIST_I(IE2LIST_IB(IE2LIST_FULL))
           KINT2_FSAVE = KINT2_A(IE2ARR_F)
           KINT2_A(IE2ARR_F) = KINT2_INI
C             FI_FROM_INIINT(FI,CINI,H,EINAC,IHOLETP)
           CALL FI_FROM_INIINT(WORK(KFI),WORK(KMOMO),WORK(KH),
     &                         ECORE_HEX,3)
           ECORE = ECORE_ORIG + ECORE_HEX
           CALL COPVEC(WORK(KFI),WORK(KINT1),NINT1)
           IF(NTEST.GE.100) THEN
             WRITE(6,*) ' ECORE_ORIG, ECORE_HEX, ECORE(2) ',
     &                    ECORE_ORIG, ECORE_HEX, ECORE
           END IF
           CALL FA_FROM_INIINT
     &     (WORK(KFA),WORK(KMOMO),WORK(KMOMO),dbl_mb(KRHO1),1)
*. and   redirect integral fetcher back to actual integrals
           KINT2 = KINT_2EMO
           KINT2_A(IE2ARR_F) = KINT2_FSAVE
*. Fock matrix in KF
          CALL FOCK_MAT_STANDARD(WORK(KF),2,WORK(KFI),WORK(KFA))
          END IF ! IINNER .ne.1
*
*. Construct orbital gradient
*
          IF(IPRNT.GE.10) WRITE(6,*) ' Construction of E1: '
          XKAPPA_NORM = SQRT(INPROD(WORK(KLKAPPA),WORK(KLKAPPA),NOOEXC))
          IF(I_USE_BR_OR_E1.EQ.1.OR.XKAPPA_NORM.EQ.0.0D0) THEN
*. Brillouin vector from Fock matrix is used
           CALL E1_FROM_F(WORK(KLE1),WORK(KF),1,WORK(KLOOEXC),
     &                   WORK(KLOOEXCC),
     &                   NOOEXC,NTOOB,NTOOBS,NSMOB,IBSO,IREOST)
          ELSE
*. Calculate gradient at non-vanishing Kappa
*. Complete Brillouin matrix
C              GET_BRT_FROM_F(BRT,F)
          CALL GET_BRT_FROM_F(WORK(KLBR),WORK(KF))
C              E1_MCSCF_FOR_GENERAL_KAPPA(E1,F,KAPPA)
          CALL E1_MCSCF_FOR_GENERAL_KAPPA(WORK(KLE1),WORK(KLBR),
     &         WORK(KLKAPPA))
          END IF
          IF(NTEST.GE.1000) THEN
            WRITE(6,*) ' E1, Gradient: '
            CALL WRTMAT(WORK(KLE1),1,NOOEXC,1,NOOEXC)
          END IF
*
          E1NRM = SQRT(INPROD(WORK(KLE1),WORK(KLE1),NOOEXC))
          IF(IPRNT.GE.2) WRITE(6,*) ' Norm of orbital gradient ', E1NRM
          WORK(KL_SUMMARY-1+(IOUT-1)*NITEM+1) = E1NRM
*
* ==========================
* Two step Newton procedure
* ==========================
*
          IF(I_DO_NEWTON.EQ.1) THEN
*
*. Transform gradient to diagonal basis
*
*. (save original gradient)
            CALL COPVEC(WORK(KLE1),WORK(KLE1B),NOOEXC)
            CALL MATVCC(WORK(KLE2F),WORK(KLE1),WORK(KLE2SC),
     &           NOOEXC,NOOEXC,1)
            CALL COPVEC(WORK(KLE2SC),WORK(KLE1),NOOEXC)
*
*. Solve shifted NR equations with step control
*
*           SOLVE_SHFT_NR_IN_DIAG_BASIS(
*    &            E1,E2,NDIM,STEP_MAX,TOLERANCE,X,ALPHA)A
            CALL SOLVE_SHFT_NR_IN_DIAG_BASIS(WORK(KLE1),WORK(KLE2VL),
     &           NOOEXC,STEP_MAX,TOLER,WORK(KLSTEP),ALPHA,DELTA_E_PRED)
            XNORM_STEP = SQRT(INPROD(WORK(KLSTEP),WORK(KLSTEP),NOOEXC))
*. Is step close to max
            I_CLOSE_TO_MAX = 0 
            IF(0.8D0.LE.XNORM_STEP/STEP_MAX) I_CLOSE_TO_MAX  = 1
*
            WORK(KL_SUMMARY-1+(IOUT-1)*NITEM+2) = 
     &      WORK(KL_SUMMARY-1+(IOUT-1)*NITEM+2) + XNORM_STEP
            IF(IPRNT.GE.2) WRITE(6,'(A,2(2X,E12.5))')
     &      ' Norm of step and predicted energy change = ',
     &       XNORM_STEP, DELTA_E_PRED
*. transform step to original basis
            CALL MATVCC(WORK(KLE2F),WORK(KLSTEP),WORK(KLE2SC),
     &           NOOEXC,NOOEXC,0)
            CALL COPVEC(WORK(KLE2SC),WORK(KLSTEP),NOOEXC)
            IF(NTEST.GE.1000) THEN
              WRITE(6,*) ' Step in original basis:'
              CALL WRTMAT(WORK(KLSTEP),1,NOOEXC,1,NOOEXC)
            END IF
*. Is direction down-hills
            E1STEP = INPROD(WORK(KLSTEP),WORK(KLE1B),NOOEXC)
            IF(IPRNT.GE.2) WRITE(6,'(A,E12.5)')
     &      ' < E1!Step> = ', E1STEP
            IF(E1STEP.GT.0.0D0) THEN
             WRITE(6,*) ' Warning: step is in uphill direction '
            END IF
*. Energy for rotated orbitals
*
            ONE = 1.0D0
            CALL VECSUM(WORK(KLKAPPA),WORK(KLKAPPA),WORK(KLSTEP),
     &      ONE,ONE,NOOEXC)
            XNORM2 = SQRT(INPROD(WORK(KLKAPPA),WORK(KLKAPPA),NOOEXC))
            WRITE(6,*) ' Norm of updated kappa step =', XNORM2
            ENERGY1 = EMCSCF_FROM_KAPPA(WORK(KLKAPPA))
            ENEW = ENERGY1
            WRITE(6,*) ' Energy for rotated orbitals', ENERGY1
*. Compare old and new energy to decide with to do
            DELTA_E_ACT = ENEW-EOLD
            E_RATIO = DELTA_E_ACT/DELTA_E_PRED  
            IF(IPRNT.GE.2) WRITE(6,'(A,3(2X,E12.5))') 
     &      ' Actual and predicted energy change, ratio ', 
     &      DELTA_E_ACT, DELTA_E_PRED,E_RATIO
*
            IF(E_RATIO.LT.0.0D0) THEN
             WRITE(6,*) ' Trustradius reduced '
             RED_FACTOR = 2.0D0
             STEP_MAX = STEP_MAX/RED_FACTOR
             WRITE(6,*) ' New trust-radius ', STEP_MAX
            END IF
            IF(E_RATIO.GT.0.8D0.AND.I_CLOSE_TO_MAX.EQ.1) THEN
             WRITE(6,*) ' Trustradius increased '
             XINC_FACTOR = 2.0D0
             STEP_MAX = STEP_MAX*XINC_FACTOR
             WRITE(6,*) ' New trust-radius ', STEP_MAX
            END IF
*
            IF((ABS(DELTA_E_ACT).GT.THRES_FOR_ENTER_LINSEA).AND.
     &         (I_DO_LINSEA_MCSCF.EQ.1.OR.
     &         I_DO_LINSEA_MCSCF.EQ.2.AND.EOLD.GT.ENEW)) THEN
*
*. line-search for orbital optimization
*
C                 LINES_SEARCH_BY_BISECTION(FUNC,REF,DIR,NVAR,XINI,
C    &            XFINAL,FFINAL,IKNOW,F0,FXINI)
*. Step was added to Kappa when calculating energy, get Kappa back
              ONE = 1.0D0
              ONEM = -1.0D0
              CALL VECSUM(WORK(KLKAPPA),WORK(KLKAPPA),WORK(KLSTEP),
     &        ONE,ONEM,NOOEXC)
              CALL LINES_SEARCH_BY_BISECTION(EMCSCF_FROM_KAPPA,
     &             WORK(KLKAPPA),WORK(KLSTEP),NOOEXC,ONE,XFINAL,FFINAL,
     &             2, EOLD, ENEW)
              ENEW = FFINAL
              IF(IPRNT.GE.2) WRITE(6,*) ' Line search value of X = ',
     &        XFINAL
              XKAPPA_NORM2 = 
     &        SQRT(INPROD(WORK(KLKAPPA),WORK(KLKAPPA),NOOEXC))
              CALL VECSUM(WORK(KLKAPPA),WORK(KLKAPPA),WORK(KLSTEP),
     &             ONE, XFINAL,NOOEXC)
            END IF! line search should be entered
            IF(NTEST.GE.1000) THEN
              WRITE(6,*) ' Updated total Kappa '
              CALL WRTMAT(WORK(KLKAPPA),1,NOOEXC,1,NOOEXC)
            END IF
          END IF! Newton method
          CALL MEMCHK2('AF_NEW')
          IF(I_DO_UPDATE.EQ.1) THEN
*
* ====================
*  Update procedure
* ====================
*
*. Update Hessian
            IF(IINNER.EQ.1) THEN
*. Just save current info
              CALL COPVEC(WORK(KLE1),WORK(KLE1PREV),NOOEXC)
              CALL COPVEC(WORK(KLKAPPA),WORK(KLKPPREV),NOOEXC)
              NMAT_UPD = 0
            ELSE
C             HESUPV (E2,AMAT,AVEC,
C    &                 X,E1,VEC2,
C    &                 VEC3,NVAR,IUPDAT,IINV,VEC1,NMAT,
C    &                 LUHFIL,DISCH,IHSAPR,IBARR,E2,VEC4)
C            HESUPV (HDIAG,A,AVEC,X,G,XPREV,GPREV,NVAR,
C    &                   IUPDAT,IINV,SCR,NMAT,LUHFIL,DISCH,
C    &                   IHSAPR,IB,E2,VEC4)

*. Update on inverse
              IINV = 1
*. Initial approximation is a cholesky factorized matrix
              IHSAPR = 3
              CALL HESUPV(WORK(KLE2),WORK(KLRANK2),WORK(KLUPDVEC),
     &             WORK(KLKAPPA),WORK(KLE1),WORK(KLKPPREV),
     &             WORK(KLE1PREV),NOOEXC,I_UPDATE_MET,IINV,
     &             WORK(KLCLKSCR),NMAT_UPD,LUHFIL,DISCH,IHSAPR,
     &             WORK(KLIBENV),WORK(KLE2),WORK(KLEXCSCR))
*. Forget the first(when starting out with exact Hessian)
              NMAT_UPD = NMAT_UPD + 1
            END IF! IINNER = 1
*
*. New search direction = step
*==============================
*
*. Inverse initial Hessian approximation times gradient
            IF(IHSAPR.EQ.1) THEN
*. Just inverse diagonal (in E2) times gradient
              CALL VVTOV(WORK(KLE2),WORK(KLE1),WORK(KLSTEP),NOOEXC)
            ELSE
              CALL COPVEC(WORK(KLE1),WORK(KLCLKSCR),NOOEXC)
C                  CLSKHE(AL,X,B,NDIM,IB,IALOFF,ITASK,INDEF)
              CALL CLSKHE(WORK(KLE2),WORK(KLSTEP),WORK(KLCLKSCR),
     &             NOOEXC,WORK(KLIBENV),WORK(KLEXCSCR),2,INDEF)
            END IF
            IF(NTEST.GE.10000) THEN
              WRITE(6,*) ' Contribution from H(ini) to (-1) step:'
              CALL WRTMAT(WORK(KLSTEP),1,NOOEXC,1,NOOEXC)
            END IF
*. And the rank-two updates
            IF(NMAT_UPD.NE.0) THEN
C                SLRMTV(NMAT,NVAR,A,AVEC,NRANK,VECIN,VECOUT,IZERO,
C    &                  DISCH,LUHFIL)
              IZERO = 0
              CALL SLRMTV(NMAT_UPD,NOOEXC,WORK(KLRANK2),WORK(KLUPDVEC),
     &                    2,WORK(KLE1),WORK(KLSTEP),IZERO,DISCH,LUHFIL)
            END IF
*. And the proverbial minus 1
            ONEM = -1.0D0
            CALL SCALVE(WORK(KLSTEP),ONEM,NOOEXC)
*. Check norm and reduce to STEP_MAX if required
            STEP_NORM = SQRT(INPROD(WORK(KLSTEP),WORK(KLSTEP),NOOEXC))
            IF(STEP_NORM.GT.STEP_MAX) THEN
              FACTOR = STEP_MAX/STEP_NORM
              IF(IPRNT.GE.2) 
     &        WRITE(6,'(A,E8.2)') ' Step reduced by factor = ', FACTOR
              CALL SCALVE(WORK(KLSTEP),FACTOR,NOOEXC)
            END IF
*
            IF(NTEST.GE.1000) THEN
              WRITE(6,*) ' Step:'
              CALL WRTMAT(WORK(KLSTEP),1,NOOEXC,1,NOOEXC)
            END IF
*. Is direction down-hills
            E1STEP = INPROD(WORK(KLSTEP),WORK(KLE1),NOOEXC)
            IF(IPRNT.GE.2) WRITE(6,'(A,E12.5)')
     &      '  < E1!Step> = ', E1STEP
            IF(E1STEP.GT.0.0D0) THEN
             WRITE(6,*) ' Warning: step is in uphill direction '
             WRITE(6,*) ' Sign of step is changed '
             ONEM = -1.0D0
             CALL SCALVE(WORK(KLSTEP),ONEM,NOOEXC)
            END IF
            XNORM_STEP = SQRT(INPROD(WORK(KLSTEP),WORK(KLSTEP),NOOEXC))
            WORK(KL_SUMMARY-1+(IOUT-1)*NITEM+2) = 
     &      WORK(KL_SUMMARY-1+(IOUT-1)*NITEM+2) + XNORM_STEP
            IF(IPRNT.GE.2) WRITE(6,'(A,E12.5)')
     &      '  Norm of step  = ', XNORM_STEP
*
*. Determine step length along direction
*. ======================================
*
*. Energy for rotated orbitals
*
            ONE = 1.0D0
            CALL VECSUM(WORK(KLKAPPA),WORK(KLKAPPA),WORK(KLSTEP),
     &      ONE,ONE,NOOEXC)
            XNORM2 = SQRT(INPROD(WORK(KLKAPPA),WORK(KLKAPPA),NOOEXC))
            WRITE(6,'(A,E12.5)') 
     &      '  Norm of total kappa = ', XNORM2
            ENERGY1 = EMCSCF_FROM_KAPPA(WORK(KLKAPPA))
            ENEW = ENERGY1
            WRITE(6,*) ' Energy for rotated orbitals', ENERGY1
*. Compare old and new energy to decide with to do
            DELTA_E_ACT = ENEW-EOLD
            IF(IPRNT.GE.2) WRITE(6,'(A,3(2X,E9.3))') 
     &      '  Actual energy change without linesearch ', DELTA_E_ACT
*
            IF((ABS(DELTA_E_ACT).GT.THRES_FOR_ENTER_LINSEA).AND.
     &         (I_DO_LINSEA_MCSCF.EQ.1.OR.
     &         I_DO_LINSEA_MCSCF.EQ.2.AND.EOLD.GT.ENEW)) THEN
*
*. line-search for orbital optimization
*
*. Step was added to Kappa when calculating energy, get Kappa back
              ONE = 1.0D0
              ONEM = -1.0D0
              CALL VECSUM(WORK(KLKAPPA),WORK(KLKAPPA),WORK(KLSTEP),
     &        ONE,ONEM,NOOEXC)
              CALL LINES_SEARCH_BY_BISECTION(EMCSCF_FROM_KAPPA,
     &             WORK(KLKAPPA),WORK(KLSTEP),NOOEXC,ONE,XFINAL,FFINAL,
     &             2, EOLD, ENEW)
              ENEW = FFINAL
              IF(IPRNT.GE.2) WRITE(6,'(A,E9.3)') 
     &        '  Step-scaling parameter from lineseach = ', XFINAL
              XKAPPA_NORM2 = 
     &        SQRT(INPROD(WORK(KLKAPPA),WORK(KLKAPPA),NOOEXC))
              CALL VECSUM(WORK(KLKAPPA),WORK(KLKAPPA),WORK(KLSTEP),
     &             ONE, XFINAL,NOOEXC)
              DELTA_E_ACT = ENEW-EOLD
              IF(IPRNT.GE.2) WRITE(6,'(A,3(2X,E9.3))') 
     &        '  Actual energy change with  linesearch ', DELTA_E_ACT
            END IF! line search should be entered
*    
            IF(ABS(DELTA_E_ACT).LT.THRES_E_INNER) THEN
             WRITE(6,*) ' Inner iterations converged '
             CONV_INNER = .TRUE.
            END IF
*
            IF(NTEST.GE.1000) THEN
               WRITE(6,*) ' Updated total Kappa '
               CALL WRTMAT(WORK(KLKAPPA),1,NOOEXC,1,NOOEXC)
            END IF
          END IF ! Update method
*
*=======================================
*. The new and improved MO-coefficients
*=======================================
*
*. Obtain exp(-kappa)
          CALL MEMCHK2('BE_NWM')
C              GET_EXP_MKAPPA(EXPMK,KAPPAP,IOOEXC,NOOEXC)
          CALL GET_EXP_MKAPPA(WORK(KLMO1),WORK(KLKAPPA),
     &                        WORK(KLOOEXCC),NOOEXC)
          CALL MEMCHK2('AF_EMK')
*. And new MO-coefficients
          CALL MULT_BLOC_MAT(WORK(KLMO2),WORK(KMOREF),WORK(KLMO1),
     &         NSMOB,NTOOBS,NTOOBS,NTOOBS,NTOOBS,NTOOBS,NTOOBS,0)
          CALL COPVEC(WORK(KLMO2),WORK(KMOMO),LEN_CMO)
          CALL MEMCHK2('AF_ML1')
*. And the new MO-AO coefficients
C?        WRITE(6,*) '  KMOAO_ACT = ', KMOAO_ACT
          CALL MULT_BLOC_MAT(WORK(KMOAO_ACT),WORK(KMOAOIN),WORK(KMOMO),
     &       NSMOB,NTOOBS,NTOOBS,NTOOBS,NTOOBS,NTOOBS,NTOOBS,0)
          CALL MEMCHK2('AF_ML2')
          IF(IPRNT.GE.100) THEN
            WRITE(6,*) ' Updated MO-coefficients'
            CALL APRBLM2(WORK(KMOMO),NTOOBS,NTOOBS,NSMOB,0)
          END IF
          IF(IRESET_KAPPA_IN_OR_OUT.EQ.1) THEN
            CALL COPVEC(WORK(KMOMO),WORK(KMOREF),LEN_CMO)
          END  IF
          CALL MEMCHK2('AF_NWM')
*
*
*  ===========================================================
*. CI in inner its- should probably be moved (but not removed)
*  ===========================================================
*
          I_DO_CI_IN_INNER_ITS = 0
          IF(I_MAY_DO_CI_IN_INNER_ITS.EQ.1.AND.I_SHIFT_E2.EQ.0.AND.
     &       XNORM2.LT.XKAPPA_THRES.AND.IOUT.GE.MIN_OUT_IT_WITH_CI) THEN
            IF(IPRNT.GE.10) WRITE(6,*) ' CI in inner it '
            I_DO_CI_IN_INNER_ITS = 1
*
*. Transform integrals to current set of MO's
*
            IF(IPRNT.GE.10) WRITE(6,*) ' Integral transformation:' 
            KINT2 = KINT_2EMO
            CALL COPVEC(WORK(KINT1_INI),WORK(KINT1O),NINT1)
            CALL COPVEC(WORK(KINT2_INI),WORK(KINT2),NINT2)
*. Flag type of integral list to be obtained
C           IE2LIST_A, IOCOBTP_A,INTSM_A
*. Flag for integrals with zero free index: energy 
*. Problem: raise!!
            IE2LIST_A = IE2LIST_0F
            IE2LIST_A = IE2LIST_4F
            IOCOBTP_A = 2
            INTSM_A = 1
            CALL TRAINT
*
            CALL COPVEC(WORK(KINT1),WORK(KH),NINT1)
*. Calculate inactive Fock matrix from integrals over initial orbitals
            IE2ARR_F = IE2LIST_I(IE2LIST_IB(IE2LIST_FULL))
            KINT2_FSAVE = KINT2_A(IE2ARR_F)
            KINT2_A(IE2ARR_F) = KINT2_INI
            CALL FI_FROM_INIINT(WORK(KFI),WORK(KMOMO),WORK(KH),
     &                          ECORE_HEX,3)
            ECORE = ECORE_ORIG + ECORE_HEX
            CALL COPVEC(WORK(KFI),WORK(KINT1),NINT1)
            IF(NTEST.GE.10000) THEN
              WRITE(6,*) ' ECORE_ORIG, ECORE_HEX, ECORE(2) ',
     &                     ECORE_ORIG, ECORE_HEX, ECORE
            END IF
            KINT2 = KINT_2EMO
            KINT2_A(IE2ARR_F) = KINT2_FSAVE
*. The diagonal will fetch J and K integrals using GTIJKL_GN,* 
*. prepare for this routine
            IE2ARRAY_A = IE2LIST_I(IE2LIST_IB(IE2LIST_A))
*
*. Perform CI - and calculate densities
*
            IF(IPRNT.GE.10) WRITE(6,*) ' CI: '
            IRESTR = 1
            MAXIT_SAVE = MAXIT
            CALL GASCI(IREFSM,IREFSPC_MCSCF,IPRDIAL,IIUSEH0P,
     &           MPORENP_E,EREF,ERROR_NORM_FINAL,CONV_F)  
            MAXIT = MAXIT_SAVE
            WRITE(6,*) ' Energy and residual from CI :', 
     &      EREF,ERROR_NORM_FINAL
            ENEW  = EREF
          END IF! CI in inner iterations
*
*. Obtain and block diagonalize FI+FA
*
          I_DIAG_FIFA = 0
          IF(I_DIAG_FIFA.EQ.1) THEN
            IE2ARR_F = IE2LIST_I(IE2LIST_IB(IE2LIST_FULL))
            KINT2_FSAVE = KINT2_A(IE2ARR_F)
            KINT2_A(IE2ARR_F) = KINT2_INI
C                FI_FROM_INIINT(FI,CINI,H,EINAC,IHOLETP)
            CALL FI_FROM_INIINT(WORK(KFI),WORK(KMOMO),WORK(KH),
     &                      ECORE_HEX,3)
            ECORE = ECORE_ORIG + ECORE_HEX
            CALL FA_FROM_INIINT
     &      (WORK(KFA),WORK(KMOMO),WORK(KMOMO),dbl_mb(KRHO1),1)
*. Clean up
            KINT2_A(IE2ARR_F) = KINT2_FSAVE
*. Diagonalize FI+FA and save in KLMO2
            CALL VECSUM(WORK(KLMO1),WORK(KFI),WORK(KFA),ONE,ONE,NINT1)
            CALL DIAG_GASBLKS(WORK(KLMO1),WORK(KLMO2),
     &           IDUM,IDUM,IDUM,WORK(KLMO3),WORK(KLMO4),2)
*. And new MO-coefficients
            CALL MULT_BLOC_MAT(WORK(KLMO3),WORK(KMOMO),WORK(KLMO2),
     &           NSMOB,NTOOBS,NTOOBS,NTOOBS,NTOOBS,NTOOBS,NTOOBS,0)
            CALL COPVEC(WORK(KLMO3),WORK(KMOMO),LEN_CMO)
          END IF !FIFA should be diagonalized
*
          IF(CONV_INNER.AND.I_DO_CI_IN_INNER_ITS.EQ.1) THEN
            CONVER = .TRUE.
            GOTO 1001
          END IF
          IF(CONV_INNER) GOTO 901
        END DO !End of loop over inner iterations
 901    CONTINUE
        CALL MEMCHK2('EN_OUT')
      END DO
*     ^ End of loop over outer iterations
 1001 CONTINUE
      IF(CONVER) THEN
        WRITE(6,*) 
     &  ' Convergence of MCSCF was obtained in ', NOUTIT,' iterations'
      ELSE
        WRITE(6,*) 
     &  ' Convergence of MCSCF was not obtained in ', NOUTIT, 
     &  'iterations'
      END IF
      WRITE(6,'(A,I4)') 
     &'  Total number of inner iterations ', N_INNER_TOT
*
*
*. Finalize: Transform integrals to final MO's, obtain
*  norm of CI- and orbital gradient
*
*
*. Expansion of final orbitals in AO basis, pt in KLMO2
      CALL MULT_BLOC_MAT(WORK(KLMO2),WORK(KMOAOIN),WORK(KMOMO),
     &       NSMOB,NTOOBS,NTOOBS,NTOOBS,NTOOBS,NTOOBS,NTOOBS,0)
      CALL COPVEC(WORK(KLMO2),WORK(KMOAO_ACT),LEN_CMO)
      CALL COPVEC(WORK(KLMO2),WORK(KMOAOUT),LEN_CMO)
      WRITE(6,*) 
     &' Final MO-AO transformation stored in MOAOIN, MOAO_ACT, MOAOUT'
*. Integral transformation
      KINT2 = KINT_2EMO
      CALL COPVEC(WORK(KINT1_INI),WORK(KINT1O),NINT1)
      CALL COPVEC(WORK(KINT2_INI),WORK(KINT2),NINT2)
*. Flag for integrals with one free index: energy + gradient
      IE2LIST_A = IE2LIST_1F
      IE2LIST_A = IE2LIST_4F
      IOCOBTP_A = 1
      INTSM_A = 1
      CALL TRAINT
      CALL COPVEC(WORK(KINT1),WORK(KH),NINT1)
*. Calculate inactive Fockmatrix -
      KINT2 = KINT2_INI
      IF(ITRA_ROUTE.EQ.2) THEN
        IE2ARR_F = IE2LIST_I(IE2LIST_IB(IE2LIST_FULL))
        KINT2_FSAVE = KINT2_A(IE2ARR_F)
        KINT2_A(IE2ARR_F) = KINT2_INI
      END IF
      CALL FI_FROM_INIINT(WORK(KFI),WORK(KMOMO),WORK(KH),
     &                    ECORE_HEX,3)
      IF(IPRNT.GE.100) WRITE(6,*) ' FI constructed '
      IF(ITRA_ROUTE.EQ.2) KINT2_A(IE2ARR_F) = KINT2_FSAVE
      CALL COPVEC(WORK(KFI),WORK(KINT1),NINT1)
      ECORE = ECORE_ORIG + ECORE_HEX
      KINT2 = KINT_2EMO
*. And 0 CI iterations with new integrals
      MAXIT_SAVE = MAXIT
      MAXIT = 1
      IRESTR = 1
*. and normal density print
      IPRDEN = IPRDEN_SAVE 
      CALL GASCI(IREFSM,IREFSPC_MCSCF,IPRDIA,IIUSEH0P,
     &            MPORENP_E,EREF,ERROR_NORM_FINAL_CI,CONV_F)
      EFINAL = EREF
      MAXIT = MAXIT_SAVE
*. Current orbital gradient
*. Active Fock matrix
      KINT2 = KINT2_INI
      IF(ITRA_ROUTE.EQ.2) THEN
        IE2ARR_F = IE2LIST_I(IE2LIST_IB(IE2LIST_FULL))
        KINT2_FSAVE = KINT2_A(IE2ARR_F)
        KINT2_A(IE2ARR_F) = KINT2_INI
      END IF
      CALL FA_FROM_INIINT
     &(WORK(KFA),WORK(KMOMO),WORK(KMOMO),dbl_mb(KRHO1),1)
      IF(IPRNT.GE.100) WRITE(6,*) ' FA constructed '
      KINT2 = KINT_2EMO
      IF(ITRA_ROUTE.EQ.2) KINT2_A(IE2ARR_F) = KINT2_FSAVE
*
      CALL FOCK_MAT_STANDARD(WORK(KF),2,WORK(KINT1),WORK(KFA))
      IF(IPRNT.GE.100) WRITE(6,*) ' F constructed '
      CALL E1_FROM_F(WORK(KLE1),WORK(KF),1,WORK(KLOOEXC),
     &               WORK(KLOOEXCC),
     &               NOOEXC,NTOOB,NTOOBS,NSMOB,IBSO,IREOST)
      E1NRM_ORB = SQRT(INPROD(WORK(KLE1),WORK(KLE1),NOOEXC))
      VNFINAL = E1NRM_ORB + ERROR_NORM_FINAL_CI
*
      IF(IPRORB.GE.2) THEN
        WRITE(6,*) 
     &  ' Final MOs in initial basis (not natural or canonical)'
        CALL APRBLM2(WORK(KMOMO),NTOOBS,NTOOBS,NSMOB,0)
      END IF
*
      IF(IPRORB.GE.1) THEN
        WRITE(6,*) 
     &  ' Final MOs in AO basis (not natural or canonical)'
        CALL PRINT_CMOAO(WORK(KLMO2))
      END IF
*
*. Projection of final occupied orbitals on initial set of occupied orbitals
*
*. Obtain initial and final occupied orbitals
      ISCR(1) = 0
      ISCR(2) = NGAS
      CALL MEMMAN(KLCOCC_INI,LEN_CMO,'ADDL  ',2,'COCC_IN')
      CALL MEMMAN(KLCOCC_FIN,LEN_CMO,'ADDL  ',2,'COCC_FI')
C     CSUB_FROM_C(C,CSUB,LENSUBS,LENSUBTS,NSUBTP,ISUBTP,
      CALL CSUB_FROM_C(WORK(KMOAOIN),WORK(KLCOCC_INI),NOCOBS,ISCR_NTS,
     &                 2,ISCR,0)
      CALL CSUB_FROM_C(WORK(KLMO2),WORK(KLCOCC_FIN),NOCOBS,ISCR_NTS,
     &                 2,ISCR,0)
C     CSUB_FROM_C(C,CSUB,LENSUBS,LENSUBTS,NSUBTP,ISUBTP,IONLY_DIM)
      WRITE(6,*) 
     &' Projecting final (MO2) on initial (MO1) occupied orbitals'
      CALL PROJ_ORBSPC_ON_ORBSPC(WORK(KLCOCC_INI),WORK(KLCOCC_FIN),
     &     NOCOBS,NOCOBS)
C     PROJ_ORBSPC_ON_ORBSPC(CMOAO1,CMOAO2,NMO1PSM,NMO2PSM)
*
*. Projection of final active orbitals on initial set of active orbitals
*
*. Obtain initial and final active orbitals
      ISCR(1) = NGAS
      CALL MEMMAN(KLCOCC_INI,LEN_CMO,'ADDL  ',2,'COCC_IN')
      CALL MEMMAN(KLCOCC_FIN,LEN_CMO,'ADDL  ',2,'COCC_FI')
C     CSUB_FROM_C(C,CSUB,LENSUBS,LENSUBTS,NSUBTP,ISUBTP,
      CALL CSUB_FROM_C(WORK(KMOAOIN),WORK(KLCOCC_INI),NACOBS,ISCR_NTS,
     &                 1,ISCR,0)
      CALL CSUB_FROM_C(WORK(KLMO2),WORK(KLCOCC_FIN),NACOBS,ISCR_NTS,
     &                 1,ISCR,0)
C     CSUB_FROM_C(C,CSUB,LENSUBS,LENSUBTS,NSUBTP,ISUBTP,IONLY_DIM)
      WRITE(6,*) 
     &' Projecting final (MO2) on initial (MO1) active orbitals'
      CALL PROJ_ORBSPC_ON_ORBSPC(WORK(KLCOCC_INI),WORK(KLCOCC_FIN),
     &     NACOBS,NACOBS)
C     PROJ_ORBSPC_ON_ORBSPC(CMOAO1,CMOAO2,NMO1PSM,NMO2PSM)
*. Print summary
      CALL PRINT_MCSCF_CONV_SUMMARY(WORK(KL_SUMMARY),NOUTIT)
      WRITE(6,'(A,F20.12)') ' Final energy = ', EFINAL
      WRITE(6,'(A,F20.12)') ' Final norm of orbital gradient = ', 
     &                        E1NRM_ORB
*
C?    WRITE(6,*) ' E1NRM_ORB, ERROR_NORM_FINAL_CI = ',
C?   &             E1NRM_ORB, ERROR_NORM_FINAL_CI
C?    WRITE(6,*) ' Final energy = ', EFINAL

      CALL MEMMAN(IDUMMY, IDUMMY, 'FLUSM', IDUMMY,'AKMCSC') 
      CALL QEXIT('AKMCS')
      RETURN
      END
      SUBROUTINE AKBKSIGMA2(CB,HCB,LUC,LUHC)
*. 
*. Obtain AKBK Hamiltonian times a vector on LUC
*
*  Version where storage of complete Q-vectors have been
*  eliminated
*
* A P and a Q space has been defined, so the eigenvalue problem reads:
*
* ( H(PP)    H(PQ) ) (CP)        (CP)
* (                ) (  )   = E  (  )
* ( H(QP)    H(QQ) ) (CQ)        (CQ)
* 
* Lowdin partition the matrix to obtain
*
* [(HPP - H(PQ) (H(QQ) - E )^(-1)H(QP)]CP = E CP
*
* HQQ is assumed so simple it may be diagonalized - here
* Diagonal or block diagonal over confs
*
*. Input and output vectors are in the P-space
*
*. It is assumed that ICNFBAT = 2 and NOCSF = 0- although pieces of code
*  easing the transition to in core are included
*
*. Jeppe Olsen, Aarhus, July 2013
*. Last revision; Aug. 2013; Jeppe Olsen; H0_CSF = 1 included
*
#include "errquit.fh"
#include "mafdecls.fh"
#include "global.fh"
      INCLUDE 'implicit.inc'
      INCLUDE 'mxpdim.inc'
      INCLUDE 'wrkspc-static.inc'
      INCLUDE 'glbbas.inc'
      INCLUDE 'cstate.inc'
      INCLUDE 'cshift.inc'
      INCLUDE 'akbk.inc'
      INCLUDE 'lucinp.inc'
      INCLUDE 'cgas.inc'
      INCLUDE 'cands.inc'
      INCLUDE 'crun.inc'
      INCLUDE 'cecore.inc'
      INCLUDE 'spinfo.inc'
      INCLUDE 'stinf.inc'
      INCLUDE 'gasstr.inc'
      INCLUDE 'strinp.inc'
      INCLUDE 'oper.inc'
      INCLUDE 'csm.inc'
      INCLUDE 'orbinp.inc'
      INCLUDE 'cicisp.inc'
      INCLUDE 'ceblk.inc'
*
      CHARACTER*6 ITASK
*. Local scratch
      INTEGER ICONF_OCC(MXPORB)
      DIMENSION CB(*), HCB(*)
      LBLK = -1
      ITASK='SIGMA '
*
      IDUM = 1
      CALL MEMMAN(IDUM,IDUM,'MARK  ',1,'AKBKSI')
      CALL QENTER('AKBKSI')
*
      NTEST = 10
      IF(NTEST.GE.10) THEN
        WRITE(6,*) ' Information from AKBKSIGMA2'
        WRITE(6,*) ' ==========================='
        WRITE(6,*)
        WRITE(6,*) ' IPSPC, IQSPC = ', IPSPC, IQSPC
      END IF 
      IF(NTEST.GE.100) THEN
        WRITE(6,*) ' LUC, LUHC = ', LUC, LUHC
      END IF
      IF(NTEST.GE.1000) THEN
        WRITE(6,*) ' Input vector to AKBKSIGMA2 '
        CALL WRTVCD(CB,LUC,1,LBLK)
      END IF
*
* Allocate scratch files
*
*. For C and Sigma in det basis
      CALL FILEMAN_MINI(LU_CDET,'ASSIGN')
      CALL FILEMAN_MINI(LU_SDET,'ASSIGN')

*
*. Construct info about the block-structures in P and Q space
*
      ICSPC = IPSPC
      ISSPC = IQSPC
*
      ISSM = IREFSM
      ICSM = IREFSM
*
      ISFIRST = 1
      ICFIRST = 1
*
      MAXK1_MX = 0
      LSCMAX_MX = 0
*
      IATP = 1
      IBTP = 2
*
      NOCTPA = NOCTYP(IATP)
      NOCTPB = NOCTYP(IBTP)
*
      IOCTPA = IBSPGPFTP(IATP)
      IOCTPB = IBSPGPFTP(IBTP)
*
      NAEL = NELEC(IATP)
      NBEL = NELEC(IBTP)
C Block for storing complete or partial CI-vector
      IF(ISIMSYM.EQ.0) THEN
        LBLOCK = MXSOOB
      ELSE
        LBLOCK = MXSOOB_AS
      END IF
      ICOMP = 0
*. Allocate space for one occupation class
      IF(NOCSF.EQ.0.OR.ICNFBAT.EQ.-2) THEN
        LBLOCK  = MAX(NSD_FOR_OCCLS_MAX,MXSOOB)
      END IF
      LBLOCK = MAX(LBLOCK,LCSBLK)
      IF(NTEST.GE.100) THEN
        WRITE(6,*) ' TEST: LCSBLK, LBLOCK, MXSOOB  = ',
     &                     LCSBLK, LBLOCK, MXSOOB
      END IF

      NTESTL = 000
      IF(ISFIRST.EQ.1) THEN
        CALL Z_BLKFO_FOR_CISPACE(ISSPC,ISSM,LBLOCK,ICOMP,
     &       NTESTL,NSBLOCK,NSBATCH,
     &       int_mb(KSIOIO),int_mb(KSBLTP),NSOCCLS_ACT,
     &       dbl_mb(KSIOCCLS_ACT),
     &       int_mb(KSLBT),WORK(KSLEBT),WORK(KSLBLK),WORK(KSI1BT),
     &       int_mb(KSIBT),
     &       WORK(KSNOCCLS_BAT),WORK(KSIBOCCLS_BAT),ILTEST)
        NSOCCLS = NSOCCLS_ACT
      END IF
      IF(ICFIRST.EQ.1) THEN
        CALL Z_BLKFO_FOR_CISPACE(ICSPC,ICSM,LBLOCK,ICOMP,
     &       NTESTL,NCBLOCK,NCBATCH,
     &       int_mb(KCIOIO),int_mb(KCBLTP),NCOCCLS_ACT,
     &       dbl_mb(KCIOCCLS_ACT),
     &       int_mb(KCLBT),WORK(KCLEBT),WORK(KCLBLK),WORK(KCI1BT),
     &       int_mb(KCIBT),
     &       WORK(KCNOCCLS_BAT),WORK(KCIBOCCLS_BAT),ILTEST)
        NCOCCLS = NCOCCLS_ACT
      END IF
*
      NPBLK = NCBLOCK
      NPBATCH = NCBATCH
      IF(NTEST.GE.1000)
     &WRITE(6,*) '  NCOCCLS, NPBLK = ', NCOCCLS, NPBLK
      NPSD = IELSUM(WORK(KCLBLK),NPBLK)
*
      IF(I12.EQ.2) THEN
        IDOH2 = 1
      ELSE
        IDOH2 = 0
      END IF
*
* Obtain J and K matrices for later use
*
      CALL MEMMAN(KLJ,NTOOB**2,'ADDL  ',2,'IIJJ  ')
      CALL MEMMAN(KLK,NTOOB**2,'ADDL  ',2,'IJJI  ')
*
*. J(I,J) = (II!JJ), K(I,J) = (IJ!JI)
*
      CALL GTJK(WORK(KLJ),WORK(KLK),NTOOB,XDUM,IREOTS)
*
* Scratch space for diagonal

*. largest number of protype dets: that of maxop
      NPDT_MAX = NPCMCNF(MAXOP+1)
      NPCS_MAX = NPCSCNF(MAXOP+1)
*
      NEL = NELFTP(IATP) + NELFTP(2)
*
      IF(NTEST.GE.100)
     &WRITE(6,*) ' NPDT_NAX, NPCS_MAX = ', NPDT_MAX, NPCS_MAX
      LISCR = 2*NPDT_MAX*NEL + NPDT_MAX + 6*NACOB
      LRSCR = 2*NPDT_MAX**2
      CALL MEMMAN(KLISCR,LISCR,'ADDL  ',1,'IS_CHC')
      CALL MEMMAN(KLRSCR,LRSCR,'ADDL  ',2,'RS_CHC')
      LCSFHCSF = NPCS_MAX**2
      CALL MEMMAN(KLCSFHCSF,LCSFHCSF,'ADDL  ',2,'CSHCS ')
*. For holding info on largest batch = occupation class
      NBLK_BAT_MAX = IMNMX(int_mb(KSLBT),NSBATCH,2)
      CALL MEMMAN(KEIBT,8*NBLK_BAT_MAX,'ADDL  ',2,'EBT   ')
      CALL MEMMAN(KELBT,1,'ADDL ',2,'ELBT  ')
      CALL MEMMAN(KEIOCCLS_ACT,1,'ADDL  ',2,'EIOCCL')
C     KEIBT,NEBLK,NEOCCLS,KEIOCCLS_ACT,KELBT
*
* 1: Transfer C from CSF to SD/CM basis 
*
      IF(ICNFBAT.EQ.1) THEN
*. In core
        CALL CSDTVCM(CB,WORK(KCOMVEC1_SD),WORK(KCOMVEC2_SD),
     &               1,0,ICSM,ICSPC,2)
      ELSE
*. Not in core- write determinant expansion on LU_CDET
       CALL CSDTVCMN(CB,HCB,dbl_mb(KVEC3),
     &      1,0,ICSM,ICSPC,2,2,LU_CDET,LUC,NCOCCLS_ACT,
     &      dbl_mb(KCIOCCLS_ACT),int_mb(KCIBT),int_mb(KCLBT))
      END IF
* 2: HPP CP (in and out in SD/CM), save on LU_SDET
      ICSPC = IPSPC
      ISSPC = IQSPC
      CALL RASSG3(CB,HCB,NCBATCH,int_mb(KCLBT),WORK(KCLEBT),
     &     WORK(KCI1BT),int_mb(KCIBT),LU_CDET,LU_SDET,XDUM,XDUM,ECORE,
     &     ITASK)
*
* and next the Q-contributions
*
*. Notice: at the moment, a batch is by construction an occupation class
*.(see PART_CIV_OCC  where I_ONE_OCCLASS_PER_BATCH = 1)

      IBSBLOCK_BAT = 1
      DO IQBAT = 1, NSBATCH
C                  IFRMR(WORK,IROFF,IELMNT)
        IQ_OCCLS = dbl_mb(KSIOCCLS_ACT + IQBAT - 1)
        NSBLOCK_BAT = int_mb(KSLBT+IQ_OCCLS-1)
*. Is this occupation in P-space
C IS_IVEC_IN_LIST(IVEC,NELMNT,LIST,LLIST)
        IQINP = IS_IVEC_IN_LIST(IQ_OCCLS,1,dbl_mb(KCIOCCLS_ACT),
     &          NCOCCLS_ACT)
        IF(NTEST.GE.200) THEN
           WRITE(6,*)
           WRITE(6,*) ' ======================================'
           WRITE(6,*) ' Info for next Q-batch: '
           WRITE(6,*) ' IQBAT, IQ_OCCLS, IQINP = ',
     &                                IQBAT, IQ_OCCLS, IQINP
           WRITE(6,*) ' NSBLOCK_BAT = ', NSBLOCK_BAT
           WRITE(6,*) ' ======================================'
           WRITE(6,*)
        END IF
        IF(IQINP.EQ.0) THEN
*
* ===============================
* Calculate HQP CP for Q in batch
* ===============================
*
C         SBLOCK(NBLOCK,IBLOCK,IBOFF,CB,HCB,LUC,IRESTRICT,
C    &           LUCBLK,ICBAT_RES,ICBAT_INI,ICBAT_END,CV,
C    &           ECORE,ITASK)
          CALL SBLOCK(NSBLOCK_BAT,int_mb(KSIBT),IBSBLOCK_BAT,CB,HCB,
     &         LU_CDET,0,0,0,0,0,CV,ECORE,ITASK)
*. The batch of HQP CP is returned in HCB
*
*
*. Transform HQP CP to CSF basis and save in CB
* 
*
*. Conf info
          CALL GEN_CNF_INFO_FOR_OCCLS(IQ_OCCLS,1,IREFSM)
          NCSF_OCCLS = IELSUM(NCS_FOR_OC_OP_ACT,MAXOP+1)
          NCM_OCCLS = IELSUM(NCM_FOR_OC_OP_ACT,MAXOP+1)
          NCM_OCCLS_AB =
     &    IFRMR(WORK,KNCMAB_FOR_OCCLS,(IQ_OCCLS-1)*NSMST+IREFSM)
*. HQP CP batch in CB
          NTESTL = 0
          CALL CSDTVCB(CB,HCB,2,WORK(KDTOC),
     &        WORK(KSDREO_I(IREFSM)),NCM_OCCLS,NCM_OCCLS_AB,
     &        NCSF_OCCLS,NCN_FOR_OC_OP_ACT,
     &        0,1,NTESTL)
*
* ===============================
*. (HQQ - E)**-1 HQP for Q batch
* ===============================
*
          CALL QENTER('AKBKH0')
          IF(IH0_CSF.EQ.1) THEN
            KEBLTP = KCBLTP
            NEBLK = NSBLOCK_BAT
C                ICOPVE2(IIN,IOFF,NDIM,IOUT)
            CALL ICOPVE2(int_mb(KSIBT),(IBSBLOCK_BAT-1)*8+1,
     &           8*NSBLOCK_BAT,int_mb(KEIBT))
            CALL ICOPVE2(int_mb(KSLBT),IQBAT,1,WORK(KELBT))
            CALL ICOPVE2(dbl_mb(KSIOCCLS_ACT),IQBAT,1,
     &                   int_mb(KEIOCCLS_ACT))
            ICISTR_SAVE = ICISTR
            ICNFBAT_SAVE = ICNFBAT
            ICISTR = 1
            ICNFBAT = 1
            CALL CSDIAGM(IREFSM,3,-1,HCB,dbl_mb(KVEC3))
C                CSDIAGM(ISM,ICS,LUDIA_A,VECUT,VECSCR)
            ICISTR =ICISTR_SAVE
            ICNFBAT = ICNFBAT_SAVE
C     COMMON/EBLK/KEBLTP,KEIBT,NEBLK,NEOCCLS,KEIOCCLS_ACT,KELBT
          ELSE IF (IH0_CSF.EQ.2) THEN
            IONLY_DIAG = 1
            ISYMG = 1
            IB_OCC = 1
            IB_H0 = 1
            IDO_REO = 1
            IB_BLK = 1
            NCSF_TOT = 0
*. Construct diagonal in HCB
            DO IOPEN = 0, MAXOP
              ITYP =  IOPEN + 1
              IORB = (NEL+IOPEN)/2
              NCSF = NPCSCNF(IOPEN+1)
COLD          NCONF = NCONF_FOR_OPEN(IOPEN+1)
              NCONF = NCONF_PER_OPEN(IOPEN+1,IREFSM)
              DO  ICONF = 1, NCONF
*. Occupation
               CALL ICOPVE2(
     &              WORK(KICONF_OCC(IREFSM)),IB_OCC,IORB,ICONF_OCC)
               IF(NTEST.GE.10000) THEN
                 WRITE(6,*) ' Occupation of next conf '
                 CALL IWRTMA(ICONF_OCC,1,IORB,1,IORB)
               END IF
*. Diagonal elements (delivered as diagonal elements of complete matrix even if ISYMG=1)
               CALL CNHCN_CSF_BLK(ICONF_OCC,IOPEN,
     &         ICONF_OCC,IOPEN,WORK(KLCSFHCSF),NINOB,WORK(KDFTP),
     &         WORK(KDTOC),2,WORK(KLISCR),WORK(KLRSCR),ECORE,
     &         IONLY_DIAG,ISYMG,WORK(KLJ),WORK(KLK))
*. Extract diagonal elements 
               CALL COPDIA(WORK(KLCSFHCSF),HCB(IB_H0),NCSF,0)
C                   COPDIA(A,VEC,NDIM,IPACK)
               IF(NTEST.GE.10000) THEN
                 WRITE(6,*) 
     &           ' Added elements, IB_H0, NCSF = ', IB_H0, NCSF
                  CALL WRTMAT(HCB(IB_H0),1,NSCF,1,NCSF)
               END IF
               IB_H0 = IB_H0 + NCSF
               IB_OCC = IB_OCC + IORB
               NCSF_TOT = NCSF_TOT + NCSF
              END DO ! Loop over configurations for given IOPEN
            END DO ! Loop over IOPEN
          END IF ! IH0_CSF switch
          IF(NTEST.GE.1000) THEN
            WRITE(6,*) ' Diagonal elements: '
            CALL WRTMAT(HCB,1,NCSF_OCCLS,1,NCSF_OCCLS)
          END IF
C (HQQ-E)**-1 HQP CP in CB
C              DIAVC2(VECOUT,VECIN,DIAG,SHIFT,NDIM)
C?        WRITE(6,*)  ' Shift = ', Shift
          CALL DIAVC2(CB,CB,HCB,SHIFT,NCSF_OCCLS)
          IF(NTEST.GE.1000) THEN
            WRITE(6,*) ' (Hqq-E)**-1 HQP CP '
            CALL WRTMAT_EP(CB,1,NCSF_OCCLS,1,NCSF_OCCLS)
          END IF
*
* Transform (HQQ-E)**-1 HQP CP to SD basis and save in in KVEC4
*
          CALL QEXIT('AKBKH0')
          NTESTL = 000
          CALL CSDTVCB(CB,WORK(KVEC4),1,WORK(KDTOC),
     &        WORK(KSDREO_I(IREFSM)),NCM_OCCLS,NCM_OCCLS_AB,
     &        NCSF_OCCLS,NCN_FOR_OC_OP_ACT,
     &        0,1,NTESTL)
* ===================================
*. HPQ (HQQ - E)**-1 HQP for Q batch
* ===================================
*
          IF(NTEST.GE.1000) THEN
            WRITE(6,*)
            WRITE(6,*) ' =========================================='
            WRITE(6,*) '  calc of HPQ (HQQ - E)**-1 HQP for Q batch'
            WRITE(6,*) ' =========================================='
            WRITE(6,*)
          END IF
* We have RHS in core, fool program to think we are doing in core
          ICISTR_SAVE = ICISTR
          ICISTR = 1
*
          ICSPC = IQSPC
          ISSPC = IPSPC
*
C              SWAP_CS_TTSSARRAYS
          CALL SWAP_CS_TTSSARRAYS
          IP_B_BLK = 1
          IP_B_CM  = 1
          DO IP_BATCH = 1, NPBATCH
           NP_BLK_BAT = int_mb(KSLBT+IP_BATCH-1)
           NP_CM_BAT  = IFRMR(WORK,KSLEBT,IP_BATCH)
           IF(NTEST.GE.1000)
     &     WRITE(6,*) ' IP_BATCH, NP_BLK_BAT, NP_CM_BAT = ',
     &                  IP_BATCH, NP_BLK_BAT, NP_CM_BAT
           CALL SBLOCK(NP_BLK_BAT,int_mb(KSIBT),IP_B_BLK,CB,
     &          HCB(IP_B_CM),
     &          -1,0,0,1,IQBAT,IQBAT,WORK(KVEC4),ECORE,ITASK)
C               SBLOCK(NBLOCK,IBLOCK,IBOFF,CB,HCB,LUC,IRESTRICT,
C    &          LUCBLK,ICBAT_RES,ICBAT_INI,ICBAT_END,CV,
C    &          ECORE,ITASK)
           IP_B_BLK = IP_B_BLK + NP_BLK_BAT
           IP_B_CM  = IP_B_CM  + NP_CM_BAT
          END DO
*
          IF(NTEST.GE.1000) THEN
            WRITE(6,*) 
     &      ' Contribution to HPQ (HQQ - E)**-1 HQP for Q batch'
           CALL WRTMAT_EP(HCB,1,NPSD,1,NPSD)
          END IF
*
*. And restore standard order
          ICSPC = IPSPC 
          ISSPC = IQSPC
          CALL SWAP_CS_TTSSARRAYS
          ICISTR = ICISTR_SAVE
*. We have now another contribtion to HPP(eff) CP in CB, update sum
*. 
*. Update current sum
          CALL REWINO(LU_SDET)
C              FRMDSCN(VEC,NREC,LBLK,LU)
          CALL FRMDSCN(CB,NPBLK,LBLK,LU_SDET)
          ONE = 1.0D0
          ONEM =  -1.0D0
          CALL VECSUM(CB,CB,HCB,ONE,ONEM,NPSD)
          CALL REWINO(LU_SDET)
          CALL TODSCN2(CB,NPBLK,WORK(KCLBLK),LBLK,LU_SDET,1) 
          IF(NTEST.GE.1000) THEN
            WRITE(6,*) ' Updated LU_SDET '
            CALL WRTVCD_EP(CB,LU_SDET,1,LBLK)
          END IF
        END IF ! Q-class differed from P-class
        IBSBLOCK_BAT = IBSBLOCK_BAT + NSBLOCK_BAT  
      END DO! Loop over occupation classes of Q
*
      IF(NTEST.GE.1000) THEN
        WRITE(6,*) ' Final HPP(eff) CP in SD basis '
        CALL WRTMAT_EP(CB,1,NPSD,1,NPSD)
      END IF
*
*. We have HPP(eff) CP in SD-basis in LU_SDET, transform to CSF basis
*. and save in 
*
      IF(ICNFBAT.EQ.1) THEN
*. In core
        CALL CSDTVCM(CB,WORK(KCOMVEC1_SD),WORK(KCOMVEC2_SD),
     &               2,0,ICSM,ICSPC,2)
      ELSE
*. Not in core- write determinant expansion on LU_CDET
       CALL CSDTVCMN(HCB,CB,dbl_mb(KVEC3),
     &      2,0,ICSM,ICSPC,2,2,LU_SDET,LUHC,NCOCCLS_ACT,
     &      dbl_mb(KCIOCCLS_ACT),int_mb(KCIBT),int_mb(KCLBT))
      END IF
      IF(NTEST.GE.1000) WRITE(6,*) ' Home from CSDTVCMN '
*
      IF(NTEST.GE.1000) THEN
       WRITE(6,*) '  Final HPP(eff) CP in CSF basis '
       WRITE(6,*) ' ================================'
       CALL WRTVCD(HCB, LUHC,1,LBLK)
C           WRTVCD(SEGMNT,LU,IREW,LBLK)
      END IF
*
      CALL FILEMAN_MINI(LU_CDET,'FREE  ')
      CALL FILEMAN_MINI(LU_SDET,'FREE  ')
*
      CALL MEMMAN(IDUM,IDUM,'FLUSM ',1,'AKBKSI')
      CALL QEXIT('AKBKSI')
*
      RETURN
      END
      SUBROUTINE SWAP_CS_TTSSARRAYS
*
* The programmer has in his or her infinite wisdom decided to
* swap the C and S spaces. Swap the corresponding pointers to the TTSS arrays
*
*. Jeppe Olsen, July 25 2013, 
*
      INCLUDE 'implicit.inc'
      INCLUDE 'mxpdim.inc'
      INCLUDE 'glbbas.inc'
      INCLUDE 'cands.inc'
*
C KCLBT,KCLEBT,KCI1BT,KCIBT,KC2B,KCIOIO,KCBLTP,KCLBLK,
      CALL SWAP_TWO_INT(KCLBT,KSLBT)
      CALL SWAP_TWO_INT(KCLEBT,KSLEBT)
      CALL SWAP_TWO_INT(KCI1BT,KSI1BT)
      CALL SWAP_TWO_INT(KCIBT,KSIBT)
      CALL SWAP_TWO_INT(KC2B,KS2B)
      CALL SWAP_TWO_INT(KCIOIO,KSIOIO)
      CALL SWAP_TWO_INT(KCBLTP,KSBLTP)
      CALL SWAP_TWO_INT(KCLBLK,KSLBLK)
      CALL SWAP_TWO_INT(NCBATCH,NSBATCH)
*
      RETURN
      END
      SUBROUTINE SWAP_TWO_INT(I1,I2)
*
* Swap integers I1 and I2
*
*. Jeppe Olsen ( to avoid mistakes in swapping a number of integers...)
*
      INCLUDE 'implicit.inc'
*
      IX = I1
      I1 = I2
      I2 = IX
*
      RETURN
      END


      

      
       



