unit Udis86;

interface
uses Windows;

type
{$Z4}
  TUdType = (UD_NONE,
  //* 8 bit GPRs */
  UD_R_AL,  UD_R_CL,  UD_R_DL,  UD_R_BL,
  UD_R_AH,  UD_R_CH,  UD_R_DH,  UD_R_BH,
  UD_R_SPL, UD_R_BPL, UD_R_SIL, UD_R_DIL,
  UD_R_R8B, UD_R_R9B, UD_R_R10B,  UD_R_R11B,
  UD_R_R12B,  UD_R_R13B,  UD_R_R14B,  UD_R_R15B,

  //* 16 bit GPRs */
  UD_R_AX,  UD_R_CX,  UD_R_DX,  UD_R_BX,
  UD_R_SP,  UD_R_BP,  UD_R_SI,  UD_R_DI,
  UD_R_R8W, UD_R_R9W, UD_R_R10W,  UD_R_R11W,
  UD_R_R12W,  UD_R_R13W,  UD_R_R14W,  UD_R_R15W,

  //* 32 bit GPRs */
  UD_R_EAX, UD_R_ECX, UD_R_EDX, UD_R_EBX,
  UD_R_ESP, UD_R_EBP, UD_R_ESI, UD_R_EDI,
  UD_R_R8D, UD_R_R9D, UD_R_R10D,  UD_R_R11D,
  UD_R_R12D,  UD_R_R13D,  UD_R_R14D,  UD_R_R15D,

  //* 64 bit GPRs */
  UD_R_RAX, UD_R_RCX, UD_R_RDX, UD_R_RBX,
  UD_R_RSP, UD_R_RBP, UD_R_RSI, UD_R_RDI,
  UD_R_R8,  UD_R_R9,  UD_R_R10, UD_R_R11,
  UD_R_R12, UD_R_R13, UD_R_R14, UD_R_R15,

  //* segment registers */
  UD_R_ES,  UD_R_CS,  UD_R_SS,  UD_R_DS,
  UD_R_FS,  UD_R_GS,

  //* control registers*/
  UD_R_CR0, UD_R_CR1, UD_R_CR2, UD_R_CR3,
  UD_R_CR4, UD_R_CR5, UD_R_CR6, UD_R_CR7,
  UD_R_CR8, UD_R_CR9, UD_R_CR10,  UD_R_CR11,
  UD_R_CR12,  UD_R_CR13,  UD_R_CR14,  UD_R_CR15,

  //* debug registers */
  UD_R_DR0, UD_R_DR1, UD_R_DR2, UD_R_DR3,
  UD_R_DR4, UD_R_DR5, UD_R_DR6, UD_R_DR7,
  UD_R_DR8, UD_R_DR9, UD_R_DR10,  UD_R_DR11,
  UD_R_DR12,  UD_R_DR13,  UD_R_DR14,  UD_R_DR15,

  //* mmx registers */
  UD_R_MM0, UD_R_MM1, UD_R_MM2, UD_R_MM3,
  UD_R_MM4, UD_R_MM5, UD_R_MM6, UD_R_MM7,

  //* x87 registers */
  UD_R_ST0, UD_R_ST1, UD_R_ST2, UD_R_ST3,
  UD_R_ST4, UD_R_ST5, UD_R_ST6, UD_R_ST7,

  //* extended multimedia registers */
  UD_R_XMM0,  UD_R_XMM1,  UD_R_XMM2,  UD_R_XMM3,
  UD_R_XMM4,  UD_R_XMM5,  UD_R_XMM6,  UD_R_XMM7,
  UD_R_XMM8,  UD_R_XMM9,  UD_R_XMM10, UD_R_XMM11,
  UD_R_XMM12, UD_R_XMM13, UD_R_XMM14, UD_R_XMM15,

  UD_R_RIP,

  // Operand Types
  UD_OP_REG,  UD_OP_MEM,  UD_OP_PTR,  UD_OP_IMM,
  UD_OP_JIMM, UD_OP_CONST);

  TUdisMnemonic = (
    UD_Iinvalid,
    UD_I3dnow,
    UD_Inone,
    UD_Idb,
    UD_Ipause,
    UD_Iaaa,
    UD_Iaad,
    UD_Iaam,
    UD_Iaas,
    UD_Iadc,
    UD_Iadd,
    UD_Iaddpd,
    UD_Iaddps,
    UD_Iaddsd,
    UD_Iaddss,
    UD_Iand,
    UD_Iandpd,
    UD_Iandps,
    UD_Iandnpd,
    UD_Iandnps,
    UD_Iarpl,
    UD_Imovsxd,
    UD_Ibound,
    UD_Ibsf,
    UD_Ibsr,
    UD_Ibswap,
    UD_Ibt,
    UD_Ibtc,
    UD_Ibtr,
    UD_Ibts,
    UD_Icall,
    UD_Icbw,
    UD_Icwde,
    UD_Icdqe,
    UD_Iclc,
    UD_Icld,
    UD_Iclflush,
    UD_Iclgi,
    UD_Icli,
    UD_Iclts,
    UD_Icmc,
    UD_Icmovo,
    UD_Icmovno,
    UD_Icmovb,
    UD_Icmovae,
    UD_Icmovz,
    UD_Icmovnz,
    UD_Icmovbe,
    UD_Icmova,
    UD_Icmovs,
    UD_Icmovns,
    UD_Icmovp,
    UD_Icmovnp,
    UD_Icmovl,
    UD_Icmovge,
    UD_Icmovle,
    UD_Icmovg,
    UD_Icmp,
    UD_Icmppd,
    UD_Icmpps,
    UD_Icmpsb,
    UD_Icmpsw,
    UD_Icmpsd,
    UD_Icmpsq,
    UD_Icmpss,
    UD_Icmpxchg,
    UD_Icmpxchg8b,
    UD_Icmpxchg16b,
    UD_Icomisd,
    UD_Icomiss,
    UD_Icpuid,
    UD_Icvtdq2pd,
    UD_Icvtdq2ps,
    UD_Icvtpd2dq,
    UD_Icvtpd2pi,
    UD_Icvtpd2ps,
    UD_Icvtpi2ps,
    UD_Icvtpi2pd,
    UD_Icvtps2dq,
    UD_Icvtps2pi,
    UD_Icvtps2pd,
    UD_Icvtsd2si,
    UD_Icvtsd2ss,
    UD_Icvtsi2ss,
    UD_Icvtss2si,
    UD_Icvtss2sd,
    UD_Icvttpd2pi,
    UD_Icvttpd2dq,
    UD_Icvttps2dq,
    UD_Icvttps2pi,
    UD_Icvttsd2si,
    UD_Icvtsi2sd,
    UD_Icvttss2si,
    UD_Icwd,
    UD_Icdq,
    UD_Icqo,
    UD_Idaa,
    UD_Idas,
    UD_Idec,
    UD_Idiv,
    UD_Idivpd,
    UD_Idivps,
    UD_Idivsd,
    UD_Idivss,
    UD_Iemms,
    UD_Ienter,
    UD_If2xm1,
    UD_Ifabs,
    UD_Ifadd,
    UD_Ifaddp,
    UD_Ifbld,
    UD_Ifbstp,
    UD_Ifchs,
    UD_Ifclex,
    UD_Ifcmovb,
    UD_Ifcmove,
    UD_Ifcmovbe,
    UD_Ifcmovu,
    UD_Ifcmovnb,
    UD_Ifcmovne,
    UD_Ifcmovnbe,
    UD_Ifcmovnu,
    UD_Ifucomi,
    UD_Ifcom,
    UD_Ifcom2,
    UD_Ifcomp3,
    UD_Ifcomi,
    UD_Ifucomip,
    UD_Ifcomip,
    UD_Ifcomp,
    UD_Ifcomp5,
    UD_Ifcompp,
    UD_Ifcos,
    UD_Ifdecstp,
    UD_Ifdiv,
    UD_Ifdivp,
    UD_Ifdivr,
    UD_Ifdivrp,
    UD_Ifemms,
    UD_Iffree,
    UD_Iffreep,
    UD_Ificom,
    UD_Ificomp,
    UD_Ifild,
    UD_Ifincstp,
    UD_Ifninit,
    UD_Ifiadd,
    UD_Ifidivr,
    UD_Ifidiv,
    UD_Ifisub,
    UD_Ifisubr,
    UD_Ifist,
    UD_Ifistp,
    UD_Ifisttp,
    UD_Ifld,
    UD_Ifld1,
    UD_Ifldl2t,
    UD_Ifldl2e,
    UD_Ifldpi,
    UD_Ifldlg2,
    UD_Ifldln2,
    UD_Ifldz,
    UD_Ifldcw,
    UD_Ifldenv,
    UD_Ifmul,
    UD_Ifmulp,
    UD_Ifimul,
    UD_Ifnop,
    UD_Ifpatan,
    UD_Ifprem,
    UD_Ifprem1,
    UD_Ifptan,
    UD_Ifrndint,
    UD_Ifrstor,
    UD_Ifnsave,
    UD_Ifscale,
    UD_Ifsin,
    UD_Ifsincos,
    UD_Ifsqrt,
    UD_Ifstp,
    UD_Ifstp1,
    UD_Ifstp8,
    UD_Ifstp9,
    UD_Ifst,
    UD_Ifnstcw,
    UD_Ifnstenv,
    UD_Ifnstsw,
    UD_Ifsub,
    UD_Ifsubp,
    UD_Ifsubr,
    UD_Ifsubrp,
    UD_Iftst,
    UD_Ifucom,
    UD_Ifucomp,
    UD_Ifucompp,
    UD_Ifxam,
    UD_Ifxch,
    UD_Ifxch4,
    UD_Ifxch7,
    UD_Ifxrstor,
    UD_Ifxsave,
    UD_Ifxtract,
    UD_Ifyl2x,
    UD_Ifyl2xp1,
    UD_Ihlt,
    UD_Iidiv,
    UD_Iin,
    UD_Iimul,
    UD_Iinc,
    UD_Iinsb,
    UD_Iinsw,
    UD_Iinsd,
    UD_Iint1,
    UD_Iint3,
    UD_Iint,
    UD_Iinto,
    UD_Iinvd,
    UD_Iinvept,
    UD_Iinvlpg,
    UD_Iinvlpga,
    UD_Iinvvpid,
    UD_Iiretw,
    UD_Iiretd,
    UD_Iiretq,
    UD_Ijo,
    UD_Ijno,
    UD_Ijb,
    UD_Ijae,
    UD_Ijz,
    UD_Ijnz,
    UD_Ijbe,
    UD_Ija,
    UD_Ijs,
    UD_Ijns,
    UD_Ijp,
    UD_Ijnp,
    UD_Ijl,
    UD_Ijge,
    UD_Ijle,
    UD_Ijg,
    UD_Ijcxz,
    UD_Ijecxz,
    UD_Ijrcxz,
    UD_Ijmp,
    UD_Ilahf,
    UD_Ilar,
    UD_Ilddqu,
    UD_Ildmxcsr,
    UD_Ilds,
    UD_Ilea,
    UD_Iles,
    UD_Ilfs,
    UD_Ilgs,
    UD_Ilidt,
    UD_Ilss,
    UD_Ileave,
    UD_Ilfence,
    UD_Ilgdt,
    UD_Illdt,
    UD_Ilmsw,
    UD_Ilock,
    UD_Ilodsb,
    UD_Ilodsw,
    UD_Ilodsd,
    UD_Ilodsq,
    UD_Iloopne,
    UD_Iloope,
    UD_Iloop,
    UD_Ilsl,
    UD_Iltr,
    UD_Imaskmovq,
    UD_Imaxpd,
    UD_Imaxps,
    UD_Imaxsd,
    UD_Imaxss,
    UD_Imfence,
    UD_Iminpd,
    UD_Iminps,
    UD_Iminsd,
    UD_Iminss,
    UD_Imonitor,
    UD_Imontmul,
    UD_Imov,
    UD_Imovapd,
    UD_Imovaps,
    UD_Imovd,
    UD_Imovhpd,
    UD_Imovhps,
    UD_Imovlhps,
    UD_Imovlpd,
    UD_Imovlps,
    UD_Imovhlps,
    UD_Imovmskpd,
    UD_Imovmskps,
    UD_Imovntdq,
    UD_Imovnti,
    UD_Imovntpd,
    UD_Imovntps,
    UD_Imovntq,
    UD_Imovq,
    UD_Imovsb,
    UD_Imovsw,
    UD_Imovsd,
    UD_Imovsq,
    UD_Imovss,
    UD_Imovsx,
    UD_Imovupd,
    UD_Imovups,
    UD_Imovzx,
    UD_Imul,
    UD_Imulpd,
    UD_Imulps,
    UD_Imulsd,
    UD_Imulss,
    UD_Imwait,
    UD_Ineg,
    UD_Inop,
    UD_Inot,
    UD_Ior,
    UD_Iorpd,
    UD_Iorps,
    UD_Iout,
    UD_Ioutsb,
    UD_Ioutsw,
    UD_Ioutsd,
    UD_Ipacksswb,
    UD_Ipackssdw,
    UD_Ipackuswb,
    UD_Ipaddb,
    UD_Ipaddw,
    UD_Ipaddd,
    UD_Ipaddsb,
    UD_Ipaddsw,
    UD_Ipaddusb,
    UD_Ipaddusw,
    UD_Ipand,
    UD_Ipandn,
    UD_Ipavgb,
    UD_Ipavgw,
    UD_Ipcmpeqb,
    UD_Ipcmpeqw,
    UD_Ipcmpeqd,
    UD_Ipcmpgtb,
    UD_Ipcmpgtw,
    UD_Ipcmpgtd,
    UD_Ipextrb,
    UD_Ipextrd,
    UD_Ipextrq,
    UD_Ipextrw,
    UD_Ipinsrb,
    UD_Ipinsrw,
    UD_Ipinsrd,
    UD_Ipinsrq,
    UD_Ipmaddwd,
    UD_Ipmaxsw,
    UD_Ipmaxub,
    UD_Ipminsw,
    UD_Ipminub,
    UD_Ipmovmskb,
    UD_Ipmulhuw,
    UD_Ipmulhw,
    UD_Ipmullw,
    UD_Ipop,
    UD_Ipopa,
    UD_Ipopad,
    UD_Ipopfw,
    UD_Ipopfd,
    UD_Ipopfq,
    UD_Ipor,
    UD_Iprefetch,
    UD_Iprefetchnta,
    UD_Iprefetcht0,
    UD_Iprefetcht1,
    UD_Iprefetcht2,
    UD_Ipsadbw,
    UD_Ipshufw,
    UD_Ipsllw,
    UD_Ipslld,
    UD_Ipsllq,
    UD_Ipsraw,
    UD_Ipsrad,
    UD_Ipsrlw,
    UD_Ipsrld,
    UD_Ipsrlq,
    UD_Ipsubb,
    UD_Ipsubw,
    UD_Ipsubd,
    UD_Ipsubsb,
    UD_Ipsubsw,
    UD_Ipsubusb,
    UD_Ipsubusw,
    UD_Ipunpckhbw,
    UD_Ipunpckhwd,
    UD_Ipunpckhdq,
    UD_Ipunpcklbw,
    UD_Ipunpcklwd,
    UD_Ipunpckldq,
    UD_Ipi2fw,
    UD_Ipi2fd,
    UD_Ipf2iw,
    UD_Ipf2id,
    UD_Ipfnacc,
    UD_Ipfpnacc,
    UD_Ipfcmpge,
    UD_Ipfmin,
    UD_Ipfrcp,
    UD_Ipfrsqrt,
    UD_Ipfsub,
    UD_Ipfadd,
    UD_Ipfcmpgt,
    UD_Ipfmax,
    UD_Ipfrcpit1,
    UD_Ipfrsqit1,
    UD_Ipfsubr,
    UD_Ipfacc,
    UD_Ipfcmpeq,
    UD_Ipfmul,
    UD_Ipfrcpit2,
    UD_Ipmulhrw,
    UD_Ipswapd,
    UD_Ipavgusb,
    UD_Ipush,
    UD_Ipusha,
    UD_Ipushad,
    UD_Ipushfw,
    UD_Ipushfd,
    UD_Ipushfq,
    UD_Ipxor,
    UD_Ircl,
    UD_Ircr,
    UD_Irol,
    UD_Iror,
    UD_Ircpps,
    UD_Ircpss,
    UD_Irdmsr,
    UD_Irdpmc,
    UD_Irdtsc,
    UD_Irdtscp,
    UD_Irepne,
    UD_Irep,
    UD_Iret,
    UD_Iretf,
    UD_Irsm,
    UD_Irsqrtps,
    UD_Irsqrtss,
    UD_Isahf,
    UD_Isalc,
    UD_Isar,
    UD_Ishl,
    UD_Ishr,
    UD_Isbb,
    UD_Iscasb,
    UD_Iscasw,
    UD_Iscasd,
    UD_Iscasq,
    UD_Iseto,
    UD_Isetno,
    UD_Isetb,
    UD_Isetae,
    UD_Isetz,
    UD_Isetnz,
    UD_Isetbe,
    UD_Iseta,
    UD_Isets,
    UD_Isetns,
    UD_Isetp,
    UD_Isetnp,
    UD_Isetl,
    UD_Isetge,
    UD_Isetle,
    UD_Isetg,
    UD_Isfence,
    UD_Isgdt,
    UD_Ishld,
    UD_Ishrd,
    UD_Ishufpd,
    UD_Ishufps,
    UD_Isidt,
    UD_Isldt,
    UD_Ismsw,
    UD_Isqrtps,
    UD_Isqrtpd,
    UD_Isqrtsd,
    UD_Isqrtss,
    UD_Istc,
    UD_Istd,
    UD_Istgi,
    UD_Isti,
    UD_Iskinit,
    UD_Istmxcsr,
    UD_Istosb,
    UD_Istosw,
    UD_Istosd,
    UD_Istosq,
    UD_Istr,
    UD_Isub,
    UD_Isubpd,
    UD_Isubps,
    UD_Isubsd,
    UD_Isubss,
    UD_Iswapgs,
    UD_Isyscall,
    UD_Isysenter,
    UD_Isysexit,
    UD_Isysret,
    UD_Itest,
    UD_Iucomisd,
    UD_Iucomiss,
    UD_Iud2,
    UD_Iunpckhpd,
    UD_Iunpckhps,
    UD_Iunpcklps,
    UD_Iunpcklpd,
    UD_Iverr,
    UD_Iverw,
    UD_Ivmcall,
    UD_Ivmclear,
    UD_Ivmxon,
    UD_Ivmptrld,
    UD_Ivmptrst,
    UD_Ivmlaunch,
    UD_Ivmresume,
    UD_Ivmxoff,
    UD_Ivmread,
    UD_Ivmwrite,
    UD_Ivmrun,
    UD_Ivmmcall,
    UD_Ivmload,
    UD_Ivmsave,
    UD_Iwait,
    UD_Iwbinvd,
    UD_Iwrmsr,
    UD_Ixadd,
    UD_Ixchg,
    UD_Ixgetbv,
    UD_Ixlatb,
    UD_Ixor,
    UD_Ixorpd,
    UD_Ixorps,
    UD_Ixcryptecb,
    UD_Ixcryptcbc,
    UD_Ixcryptctr,
    UD_Ixcryptcfb,
    UD_Ixcryptofb,
    UD_Ixrstor,
    UD_Ixsave,
    UD_Ixsetbv,
    UD_Ixsha1,
    UD_Ixsha256,
    UD_Ixstore,
    UD_Iaesdec,
    UD_Iaesdeclast,
    UD_Iaesenc,
    UD_Iaesenclast,
    UD_Iaesimc,
    UD_Iaeskeygenassist,
    UD_Ipclmulqdq,
    UD_Igetsec,
    UD_Imovdqa,
    UD_Imaskmovdqu,
    UD_Imovdq2q,
    UD_Imovdqu,
    UD_Imovq2dq,
    UD_Ipaddq,
    UD_Ipsubq,
    UD_Ipmuludq,
    UD_Ipshufhw,
    UD_Ipshuflw,
    UD_Ipshufd,
    UD_Ipslldq,
    UD_Ipsrldq,
    UD_Ipunpckhqdq,
    UD_Ipunpcklqdq,
    UD_Iaddsubpd,
    UD_Iaddsubps,
    UD_Ihaddpd,
    UD_Ihaddps,
    UD_Ihsubpd,
    UD_Ihsubps,
    UD_Imovddup,
    UD_Imovshdup,
    UD_Imovsldup,
    UD_Ipabsb,
    UD_Ipabsw,
    UD_Ipabsd,
    UD_Ipshufb,
    UD_Iphaddw,
    UD_Iphaddd,
    UD_Iphaddsw,
    UD_Ipmaddubsw,
    UD_Iphsubw,
    UD_Iphsubd,
    UD_Iphsubsw,
    UD_Ipsignb,
    UD_Ipsignd,
    UD_Ipsignw,
    UD_Ipmulhrsw,
    UD_Ipalignr,
    UD_Ipblendvb,
    UD_Ipmuldq,
    UD_Ipminsb,
    UD_Ipminsd,
    UD_Ipminuw,
    UD_Ipminud,
    UD_Ipmaxsb,
    UD_Ipmaxsd,
    UD_Ipmaxud,
    UD_Ipmaxuw,
    UD_Ipmulld,
    UD_Iphminposuw,
    UD_Iroundps,
    UD_Iroundpd,
    UD_Iroundss,
    UD_Iroundsd,
    UD_Iblendpd,
    UD_Ipblendw,
    UD_Iblendps,
    UD_Iblendvpd,
    UD_Iblendvps,
    UD_Idpps,
    UD_Idppd,
    UD_Impsadbw,
    UD_Iextractps,
    UD_Iinsertps,
    UD_Imovntdqa,
    UD_Ipackusdw,
    UD_Ipmovsxbw,
    UD_Ipmovsxbd,
    UD_Ipmovsxbq,
    UD_Ipmovsxwd,
    UD_Ipmovsxwq,
    UD_Ipmovsxdq,
    UD_Ipmovzxbw,
    UD_Ipmovzxbd,
    UD_Ipmovzxbq,
    UD_Ipmovzxwd,
    UD_Ipmovzxwq,
    UD_Ipmovzxdq,
    UD_Ipcmpeqq,
    UD_Ipopcnt,
    UD_Iptest,
    UD_Ipcmpestri,
    UD_Ipcmpestrm,
    UD_Ipcmpgtq,
    UD_Ipcmpistri,
    UD_Ipcmpistrm,
    UD_Imovbe,
    UD_Icrc32,
    UD_MAX_MNEMONIC_CODE
  );
{$Z1}

  TUdLVal = Uint64; // union with all types

  TUdOperand = record
    nType   : TUdType;
    nSize   : Byte;
    nBase   : TUdType;
    nIndex  : TUdType;
    nScale  : Byte;
    nOffset : Byte;
    lVal    : TUdLVal;
    nLegacy : Uint64;
    nOpr    : Byte;
  end;

  UdRec = record
    inpHook : Pointer;
    inpFile : Pointer;
    pInpBuf : PByte;
    nInpBufSize : Uint64;
    nInpBufIndex : Uint64;
    udReserved : array [0..$15F-4] of Byte;
    mnemonic : TUdisMnemonic;
    udOperand : array [0..2] of TUdOperand;
    nError   : Byte;
    pfxRex   : Byte;
    pfxSeg   : Byte;
    pfxOpr   : Byte;
    pfxAdr   : Byte;
    pfxLock  : Byte;
    pfxStr   : Byte;
    pfxRep   : Byte;
    pfxRepe  : Byte;
    pfxRepne : Byte;
    oprMode  : Byte;
    adrMode  : Byte;
    brFar    : Byte;
    brNear   : Byte;
    bHaveMRm : Byte;
    nModRM   : Byte;
    nPrimOpcode : Byte;
    nUserOpaqueData : Pointer;
    iTabEntry : Pointer;
    le : Pointer;
  end;
  PUdRec = ^UdRec;

  TUdisDisasmError = (udErrNone = 0, udErrProcedureTooSmall, udErrJmpAtStart, udErrExecBufferTooSmallForJumpback, udErrExecBufferTooSmallForPatching, udErrExecBufferNotRelativeNear);

type
  TCallBackProc = procedure (ud : PUdRec); stdcall;

var
  g_bUdisLoaded : Boolean = False;

  UdInit           : procedure (ud : PUdRec); stdcall;
  UdSetMode        : procedure (ud : PUdRec; nMode : Byte); stdcall;
  UdSetInputBuffer : procedure (ud : PUdRec; pBuffer : PByte; nSize : SIZE_T); stdcall;
  UdDisassemble    : function  (ud : PUdRec): Cardinal; stdcall;
  UdSetSyntax      : procedure (ud : PUdRec; syn : TCallBackProc); stdcall;
  UdTranslateIntel : procedure (ud : PUdRec); stdcall;
  UdInSnAsm        : function  (ud : PUdRec): PAnsiChar;

  function UdErrorToStr(udErr : TUdisDisasmError): String;
  function UdisDisasmAtLeast(pAt : Pointer; nBufferSize : Cardinal; nByteCountToDisasm : Cardinal): Cardinal;
  function UdisDisasmAtLeastAndPatchRelatives(pAt : Pointer; nBufferSize : Cardinal; nByteCountToDisasm : Cardinal; pRelBuffer : PByte; nRelBufSize : Cardinal; var nBytesDisassembled : Cardinal): TUdisDisasmError;

implementation
  uses
    Utils,
    SysUtils;

var
  hUdis : THandle;

function UdErrorToStr(udErr : TUdisDisasmError): String;
begin
  case udErr of
    udErrNone:                          Result := 'Ok';
    udErrProcedureTooSmall:             Result := 'Procedure is too small';
    udErrJmpAtStart:                    Result := 'Jump at the start';
    udErrExecBufferTooSmallForJumpback: Result := 'Buffer too small for jumpback';
    udErrExecBufferTooSmallForPatching: Result := 'Buffer too small for patching';
    udErrExecBufferNotRelativeNear:     Result := 'Buffer is not allocated near relative jump';
  else
    Result := 'Unknown';
  end;
end;

function UdisDisasmAtLeast(pAt : Pointer; nBufferSize : Cardinal; nByteCountToDisasm : Cardinal): Cardinal;
var
  ud : UdRec;
  nBytesDisassembled : Cardinal;
begin
  UdInit(@ud);
  UdSetMode(@ud, 64);
  UdSetInputBuffer(@ud, pAt, nBufferSize);

  nBytesDisassembled := 0;
  while (nBytesDisassembled < nByteCountToDisasm) do
    begin
      nBytesDisassembled := nBytesDisassembled + UdDisassemble(@ud);
    end;
  Result := nBytesDisassembled;
end;

function UdisDisasmAtLeastAndPatchRelatives(pAt : Pointer; nBufferSize : Cardinal; nByteCountToDisasm : Cardinal; pRelBuffer : PByte; nRelBufSize : Cardinal; var nBytesDisassembled : Cardinal): TUdisDisasmError;
type
  TRelToVal = record
    ptrPatch    : Pointer;  // To be patched
    nValue      : Uint64;
    nInstrSize  : Integer;  // Size in bytes of the instruction
    nOpSizeBits : Byte;     // Size in bits of the operand in the instruction
    nSizeBits   : Byte;     // Size in bits of the data pointed by the operator
    nOffset     : Integer;
  end;
var
  ud                 : UdRec;
  nInstrSize         : Cardinal;
  nSizeBits          : Byte;
  nRelIdx            : Integer;
  nOperand           : Integer;
  nIndex             : Integer;
  nAuxOffset         : Int64;
  arPatch            : array [0..7] of TRelToVal;
  nNewRelOffset      : Integer;
  nOf                : Integer;
  nOpOffsetFromEnd   : Integer;
begin
  if nBufferSize < nByteCountToDisasm then
    begin
      Exit(udErrProcedureTooSmall);
    end;

  UdInit(@ud);
  UdSetMode(@ud, 64);
  UdSetInputBuffer(@ud, pAt, nBufferSize);
  //UdSetSyntax(@ud, @UdTranslateIntel);

  nRelIdx := 0;
  ZeroMemory(@arPatch[0], sizeof(arPatch));

  nBytesDisassembled := 0;
  while (nBytesDisassembled < nByteCountToDisasm) do
    begin
      nInstrSize := UdDisassemble(@ud);
      nBytesDisassembled := nBytesDisassembled + nInstrSize;
      Dec(nRelBufSize, nInstrSize);

      CopyMemory(pRelBuffer, ud.pInpBuf + ud.nInpBufIndex - nInstrSize, nInstrSize);

      case ud.mnemonic of
        UD_Ileave,
        UD_Iloopne,
        UD_Iloope,
        UD_Iloop,
        UD_Icall,
        UD_Iiretw, UD_Iiretd, UD_Iiretq, UD_Ijo, UD_Ijno, UD_Ijb, UD_Ijae,
        UD_Ijz, UD_Ijnz, UD_Ijbe, UD_Ija, UD_Ijs, UD_Ijns, UD_Ijp, UD_Ijnp,
        UD_Ijl, UD_Ijge, UD_Ijle, UD_Ijg, UD_Ijcxz, UD_Ijecxz, UD_Ijrcxz, UD_Ijmp:
          begin
            Exit(udErrJmpAtStart);
          end;
      else
      end;

      for nOperand := 0 to High(ud.udOperand) do
        begin
          if ud.udOperand[nOperand].nBase = UD_R_RIP then
            begin
              if Uint64(pRelBuffer) > $FFFFFFFF then
                Exit(udErrExecBufferNotRelativeNear);

              nSizeBits := ud.udOperand[nOperand].nSize;
              nNewRelOffset := Integer((pRelBuffer + nInstrSize) - (PByte(pAt) + nBytesDisassembled));

              nOpOffsetFromEnd := 0;
              for nOf := High(ud.udOperand) downto nOperand do
                begin
                  if ud.udOperand[nOf].nType = UD_OP_MEM then
                    Inc(nOpOffsetFromEnd, ud.udOperand[nOf].nOffset div 8)
                  else if ud.udOperand[nOf].nType = UD_OP_IMM then
                    Inc(nOpOffsetFromEnd, ud.udOperand[nOf].nSize div 8)
                  else if ud.udOperand[nOf].nType = UD_NONE then
                    Continue
                  else
                    Exit(udErrExecBufferNotRelativeNear); // TODO(psv): Unknown operator type
                end;

              arPatch[nRelIdx].ptrPatch := pRelBuffer + nInstrSize - nOpOffsetFromEnd;
              arPatch[nRelIdx].nOffset := Integer(ud.udOperand[nOperand].lVal) - nNewRelOffset;

              //PInteger(arPatch[nRelIdx].ptrPatch)^ := Integer(ud.udOperand[nOperand].lVal) - nNewRelOffset;

              Inc(nRelIdx);
            end;
        end;

      Inc(pRelBuffer, nInstrSize);
    end;

  // jmp r10 instruction to jump back to the function being called
  if nRelBufSize >= 3 then
    begin
      pRelBuffer[0] := $41;
      pRelBuffer[1] := $ff;
      pRelBuffer[2] := $e2;
      Dec(nRelBufSize, 3);
      Inc(pRelBuffer, 3);
    end
  else
    begin
      // Error, not enough size in the buffer for the jump back
      Exit(udErrExecBufferTooSmallForJumpback);
    end;

  for nIndex := 0 to nRelIdx-1 do
    begin
      PInteger(arPatch[nIndex].ptrPatch)^ := arPatch[nIndex].nOffset;
    end;

  Result := udErrNone;
end;

function LoadUdis: Boolean;
begin
  OutputDebugString(PWidechar('Loading UDIS ' + Format('%p', [Pointer(hUdis)])));

  hUdis := LoadLibrary('..\..\lib\udis86\libudis.dll');
  if hUdis = 0 then
    hUdis := LoadLibrary('lib\udis86\libudis.dll');

  if hUdis <> 0 then
    begin
      @UdInit := GetProcAddress(hUdis, 'ud_init');
      @UdSetMode := GetProcAddress(hUdis, 'ud_set_mode');
      @UdSetInputBuffer := GetProcAddress(hUdis, 'ud_set_input_buffer');
      @UdDisassemble := GetProcAddress(hUdis, 'ud_disassemble');
      @UdTranslateIntel := GetProcAddress(hUdis, 'ud_translate_intel');
      @UdSetSyntax := GetProcAddress(hUdis, 'ud_set_syntax');
      @UdInSnAsm := GetProcAddress(hUdis, 'ud_insn_asm');

      OutputDebugString(PWidechar('Loaded Udis86 ' + Format('%p', [Pointer(@UdInit)])));
      Result := True;
    end
  else
    begin
      OutputDebugString('Failed to load Udis86');
      Result := False;
    end;
end;

initialization
  g_bUdisLoaded := LoadUdis;
end.
