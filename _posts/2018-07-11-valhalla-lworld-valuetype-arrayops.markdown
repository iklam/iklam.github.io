---
layout: post
title:  "ValueType Array Operations on Valhalla LWorld"
date:   2018-07-11 11:00:00 -0800
categories: jekyll update
---

# Overview

I justed started getting involved with the [Vahalla LWorld project](http://mail.openjdk.java.net/pipermail/valhalla-dev/2018-January/003727.html), which is part of OpenJDK's investigation of [Value Types](http://openjdk.java.net/projects/valhalla/).

So this is what I just learned: how operations on an array of Values is much faster than an array of objects. Here's a simple test case.

```
final __ByValue class V { // A Value
    public final int v1;
    public final int v2;
    public final int v3;
    V () {
        v1 = 0;
        v2 = 0;
        v3 = 0;
    }
    public static V makeV(int v1) {
        V p = __MakeDefault V();
        p = __WithField(p.v1, v1);
        return p;
    }
}

class R {  // Plain Old Java Object (POJO)
  int r1, r2, r3;
}

public class Bench {
  public static V[] varray = new V[10000];
  public static R[] rarray = new R[10000];

  static int testv() { // operate on an array of Value
    V[] a = varray;
    int c = 0;
    for (int i=0; i<a.length; i++) {
      c += a[i].v1;
    }
    return c;
  }

  static int testr() { // operate on an array of POJO
    R[] a = rarray;
    int c = 0;
    for (int i=0; i<a.length; i++) {
      c += a[i].r1;
    }
    return c;
  }

  public static void main(String args[]) {
    testv();
    testr();
    for (int i=0; i<rarray.length; i++) {
      rarray[i] = new R();
    }
  }
}
```

To test this, you need to build from the `lworld` branch of the
valhalla repo](http://hg.openjdk.java.net/valhalla/valhalla)

# Bytecodes that Operate on an Array of Values.

Here's the testv and testr methods in bytecodes. You can see that they are identical.

```
$ javap -c Bench.class 

  static int testv();
    Code:
       0: getstatic     #2                  // Field varray:[LV;
       3: astore_0
       4: iconst_0
       5: istore_1
       6: iconst_0
       7: istore_2
       8: iload_2
       9: aload_0
      10: arraylength
      11: if_icmpge     29
      14: iload_1
      15: aload_0
      16: iload_2
      17: aaload
      18: getfield      #3                  // Field V.v1:I
      21: iadd
      22: istore_1
      23: iinc          2, 1
      26: goto          8
      29: iload_1
      30: ireturn

  static int testr();
    Code:
       0: getstatic     #4                  // Field rarray:[LR;
       3: astore_0
       4: iconst_0
       5: istore_1
       6: iconst_0
       7: istore_2
       8: iload_2
       9: aload_0
      10: arraylength
      11: if_icmpge     29
      14: iload_1
      15: aload_0
      16: iload_2
      17: aaload
      18: getfield      #5                  // Field R.r1:I
      21: iadd
      22: istore_1
      23: iinc          2, 1
      26: goto          8
      29: iload_1
      30: ireturn
```

The layout of `varray` is very different than `rarray`. On 64-bit platform with compressed oops, `rarray` looks like this

```
   @0   object header
   @8   array length
   @16  rarray[0]    - 4-byte compressed oop pointer
   @20  rarray[1]    - 4-byte compressed oop pointer
   @24  ....
```

But `varray` contains "flattened" copies of V (think about how C++ lays out an array `struct {int x, y, z;} varray[123];`), so it looks like this

```
   @0   object header
   @8   array length
   @16  rarray[0].v0, rarray[0].v1, rarray[0].v2, (filler) - 16 bytes
   @32  rarray[1].v0, rarray[1].v1, rarray[1].v2, (filler) - 16 bytes
   @48  ....
```

# Comparison of Code Generated by JIT Compiler

You can see the code generated by the JIT compiler (currently only the server JIT compiler, aka C2, is enabled for Valhalla):

```
$ java -XX:+EnableValhalla -cp classes -XX:+UnlockDiagnosticVMOptions \
    -XX:CompileCommand=quiet -XX:-BackgroundCompilation -XX:CICompilerCount=1 \
    -XX:+ValueTypePassFieldsAsArgs -XX:+ValueTypeReturnedAsFields \
    -XX:+ValueArrayFlatten -Xcomp -XX:+PrintAssembly -XX:+LogCompilation \
    -XX:CompileCommand=compileonly,Bench::testr \
    Bench

----------------------------------------------------------------------
Bench.testv()I  [0x00007f661cc6a6a0, 0x00007f661cc6a7f8]  344 bytes
[Disassembling for mach='i386:x86-64']
[Entry Point]
[Verified Entry Point]
[Constants]
  # {method} {0x00007f65eb0f53c0} 'testv' '()I' in 'Bench'
  #           [sp+0x20]  (sp of caller)
  0x00007f661cc6a6a0: mov    %eax,-0x14000(%rsp)
  0x00007f661cc6a6a7: push   %rbp
  0x00007f661cc6a6a8: sub    $0x10,%rsp         ;*synchronization entry
                                                ; - Bench::testv@-1 (line 10)

  0x00007f661cc6a6ac: mov    $0x4510965d8,%r10  ;   {oop(a 'java/lang/Class'{0x00000004510965d8} = 'Bench')}
  0x00007f661cc6a6b6: mov    0x70(%r10),%ebp    ;*getstatic varray {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@0 (line 10)

  0x00007f661cc6a6ba: mov    0xc(%r12,%rbp,8),%ecx  ;*arraylength {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@10 (line 12)
                                                ; implicit exception: dispatches to 0x00007f661cc6a7ce
  0x00007f661cc6a6bf: test   %ecx,%ecx
  0x00007f661cc6a6c1: jbe    0x00007f661cc6a7ae  ;*if_icmpge {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@11 (line 12)

  0x00007f661cc6a6c7: mov    %ecx,%r11d
  0x00007f661cc6a6ca: dec    %r11d
  0x00007f661cc6a6cd: cmp    %ecx,%r11d
  0x00007f661cc6a6d0: jae    0x00007f661cc6a7c0
  0x00007f661cc6a6d6: mov    0x10(%r12,%rbp,8),%eax  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@17 (line 13)

  0x00007f661cc6a6db: lea    (%r12,%rbp,8),%r10  ;*getstatic varray {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@0 (line 10)

  0x00007f661cc6a6df: mov    %ecx,%r8d
  0x00007f661cc6a6e2: add    $0xfffffffffffffff1,%r8d
  0x00007f661cc6a6e6: mov    $0x80000000,%r9d
  0x00007f661cc6a6ec: cmp    %r8d,%r11d
  0x00007f661cc6a6ef: cmovl  %r9d,%r8d
  0x00007f661cc6a6f3: mov    $0x1,%r11d
  0x00007f661cc6a6f9: cmp    $0x1,%r8d
  0x00007f661cc6a6fd: jle    0x00007f661cc6a791  ;*iload_1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@14 (line 13)

  0x00007f661cc6a703: movslq %r11d,%r9
  0x00007f661cc6a706: shl    $0x4,%r9           ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@17 (line 13)

  0x00007f661cc6a70a: add    0x10(%r10,%r9,1),%eax
  0x00007f661cc6a70f: add    0x20(%r10,%r9,1),%eax
  0x00007f661cc6a714: add    0x30(%r10,%r9,1),%eax
  0x00007f661cc6a719: add    0x40(%r10,%r9,1),%eax
  0x00007f661cc6a71e: add    0x50(%r10,%r9,1),%eax
  0x00007f661cc6a723: add    0x60(%r10,%r9,1),%eax
  0x00007f661cc6a728: add    0x70(%r10,%r9,1),%eax
  0x00007f661cc6a72d: add    0x80(%r10,%r9,1),%eax
  0x00007f661cc6a735: add    0x90(%r10,%r9,1),%eax
  0x00007f661cc6a73d: add    0xa0(%r10,%r9,1),%eax
  0x00007f661cc6a745: add    0xb0(%r10,%r9,1),%eax
  0x00007f661cc6a74d: add    0xc0(%r10,%r9,1),%eax
  0x00007f661cc6a755: add    0xd0(%r10,%r9,1),%eax
  0x00007f661cc6a75d: add    0xe0(%r10,%r9,1),%eax
  0x00007f661cc6a765: add    0xf0(%r10,%r9,1),%eax
  0x00007f661cc6a76d: add    0x100(%r10,%r9,1),%eax  ;*iadd {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@21 (line 13)

  0x00007f661cc6a775: add    $0x10,%r11d        ;*iinc {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@23 (line 12)

  0x00007f661cc6a779: cmp    %r8d,%r11d
  0x00007f661cc6a77c: jl     0x00007f661cc6a703  ;*if_icmpge {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@11 (line 12)

  0x00007f661cc6a77e: mov    0xe8(%r15),%r9     ; ImmutableOopMap{r10=Oop }
                                                ;*goto {reexecute=1 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@26 (line 12)

  0x00007f661cc6a785: test   %eax,(%r9)         ;*goto {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@26 (line 12)
                                                ;   {poll}
  0x00007f661cc6a788: cmp    %r8d,%r11d
  0x00007f661cc6a78b: jl     0x00007f661cc6a703
  0x00007f661cc6a791: cmp    %ecx,%r11d
  0x00007f661cc6a794: jge    0x00007f661cc6a7b0
  0x00007f661cc6a796: xchg   %ax,%ax            ;*iload_1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@14 (line 13)

  0x00007f661cc6a798: movslq %r11d,%r8
  0x00007f661cc6a79b: shl    $0x4,%r8
  0x00007f661cc6a79f: add    0x10(%r10,%r8,1),%eax  ;*iadd {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@21 (line 13)

  0x00007f661cc6a7a4: inc    %r11d              ;*iinc {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@23 (line 12)

  0x00007f661cc6a7a7: cmp    %ecx,%r11d
  0x00007f661cc6a7aa: jl     0x00007f661cc6a798
  0x00007f661cc6a7ac: jmp    0x00007f661cc6a7b0
  0x00007f661cc6a7ae: xor    %eax,%eax          ;*if_icmpge {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@11 (line 12)

  0x00007f661cc6a7b0: add    $0x10,%rsp
  0x00007f661cc6a7b4: pop    %rbp
  0x00007f661cc6a7b5: mov    0xe8(%r15),%r10
  0x00007f661cc6a7bc: test   %eax,(%r10)        ;   {poll_return}
  0x00007f661cc6a7bf: retq   
  0x00007f661cc6a7c0: mov    $0xffffff86,%esi
  0x00007f661cc6a7c5: xchg   %ax,%ax
  0x00007f661cc6a7c7: callq  0x00007f661cc2bd80  ; ImmutableOopMap{rbp=NarrowOop }
                                                ;*iload_1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@14 (line 13)
                                                ;   {runtime_call UncommonTrapBlob}
  0x00007f661cc6a7cc: ud2a                      ;*iload_1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@14 (line 13)

  0x00007f661cc6a7ce: mov    $0xfffffff6,%esi
  0x00007f661cc6a7d3: callq  0x00007f661cc2bd80  ; ImmutableOopMap{}
                                                ;*arraylength {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@10 (line 12)
                                                ;   {runtime_call UncommonTrapBlob}
  0x00007f661cc6a7d8: ud2a                      ;*iload_1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testv@14 (line 13)

  0x00007f661cc6a7da: hlt    
[snip]
```

Note that starting from `0x00007f661cc6a70a`, we have an unrolled loop of adding up
16 elements together for the `c += a[i].v1` expression. Note that the `v1` elements are spaced
out bt 16 bytes each.

In contrast, the POJO version looks like this. Although the loop body is also unrolled, the access of each element requires two loads, so it's much slower:

```
Bench.testr()I  [0x00007f2130c6a920, 0x00007f2130c6ab38]  536 bytes
[Disassembling for mach='i386:x86-64']
[Entry Point]
[Verified Entry Point]
[Constants]
  # {method} {0x00007f20f7c004a0} 'testr' '()I' in 'Bench'
  #           [sp+0x40]  (sp of caller)
  0x00007f2130c6a920: mov    %eax,-0x14000(%rsp)
  0x00007f2130c6a927: push   %rbp
  0x00007f2130c6a928: sub    $0x30,%rsp         ;*synchronization entry
                                                ; - Bench::testr@-1 (line 19)

  0x00007f2130c6a92c: mov    $0x4510965d8,%r10  ;   {oop(a 'java/lang/Class'{0x00000004510965d8} = 'Bench')}
  0x00007f2130c6a936: mov    0x74(%r10),%ebp    ;*getstatic rarray {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@0 (line 19)

  0x00007f2130c6a93a: mov    0xc(%r12,%rbp,8),%esi  ;*arraylength {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@10 (line 21)
                                                ; implicit exception: dispatches to 0x00007f2130c6aafa
  0x00007f2130c6a93f: test   %esi,%esi
  0x00007f2130c6a941: jbe    0x00007f2130c6a983  ;*if_icmpge {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@11 (line 21)

  0x00007f2130c6a943: mov    %esi,%r8d
  0x00007f2130c6a946: dec    %r8d
  0x00007f2130c6a949: cmp    %esi,%r8d
  0x00007f2130c6a94c: jae    0x00007f2130c6aadf
  0x00007f2130c6a952: mov    0x10(%r12,%rbp,8),%r10d  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6a957: mov    0xc(%r12,%r10,8),%eax  ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6a95c: lea    (%r12,%rbp,8),%r13  ;*getstatic rarray {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@0 (line 19)

  0x00007f2130c6a960: mov    %esi,%edi
  0x00007f2130c6a962: add    $0xfffffffffffffff1,%edi
  0x00007f2130c6a965: mov    $0x1,%r10d
  0x00007f2130c6a96b: mov    $0x80000000,%r9d
  0x00007f2130c6a971: cmp    %edi,%r8d
  0x00007f2130c6a974: cmovl  %r9d,%edi
  0x00007f2130c6a978: cmp    $0x1,%edi
  0x00007f2130c6a97b: jle    0x00007f2130c6aabd  ;*goto {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@26 (line 21)

  0x00007f2130c6a981: jmp    0x00007f2130c6a9a7
  0x00007f2130c6a983: xor    %eax,%eax          ;*if_icmpge {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@11 (line 21)

  0x00007f2130c6a985: add    $0x30,%rsp
  0x00007f2130c6a989: pop    %rbp
  0x00007f2130c6a98a: mov    0xe8(%r15),%r10
  0x00007f2130c6a991: test   %eax,(%r10)        ;   {poll_return}
  0x00007f2130c6a994: retq   
  0x00007f2130c6a995: nopw   0x0(%rax,%rax,1)
  0x00007f2130c6a9a0: vmovd  %xmm0,%esi
  0x00007f2130c6a9a4: mov    (%rsp),%edi        ;*iload_1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@14 (line 22)

  0x00007f2130c6a9a7: mov    0x10(%r13,%r10,4),%r11d
  0x00007f2130c6a9ac: add    0xc(%r12,%r11,8),%eax  ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6a9b1: mov    0x14(%r13,%r10,4),%r11d  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6a9b6: mov    0xc(%r12,%r11,8),%r8d  ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6a9bb: mov    0x18(%r13,%r10,4),%r9d  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6a9c0: mov    0xc(%r12,%r9,8),%ebx  ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6a9c5: mov    0x1c(%r13,%r10,4),%r11d  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6a9ca: mov    0xc(%r12,%r11,8),%ecx  ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6a9cf: mov    0x20(%r13,%r10,4),%r9d  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6a9d4: mov    0xc(%r12,%r9,8),%edx  ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6a9d9: mov    0x24(%r13,%r10,4),%r11d  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6a9de: mov    0xc(%r12,%r11,8),%ebp  ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6a9e3: mov    0x28(%r13,%r10,4),%r9d  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6a9e8: mov    0xc(%r12,%r9,8),%r14d  ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6a9ed: mov    0x2c(%r13,%r10,4),%r11d  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6a9f2: mov    0xc(%r12,%r11,8),%r11d  ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6a9f7: mov    0x30(%r13,%r10,4),%r9d  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6a9fc: mov    0xc(%r12,%r9,8),%r9d  ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6aa01: mov    %ebp,0x14(%rsp)
  0x00007f2130c6aa05: mov    %edx,0x10(%rsp)
  0x00007f2130c6aa09: mov    %ecx,0xc(%rsp)
  0x00007f2130c6aa0d: mov    %ebx,0x8(%rsp)
  0x00007f2130c6aa11: mov    %r8d,0x4(%rsp)
  0x00007f2130c6aa16: mov    %edi,(%rsp)
  0x00007f2130c6aa19: vmovd  %esi,%xmm0
  0x00007f2130c6aa1d: mov    0x34(%r13,%r10,4),%ecx  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6aa22: mov    0xc(%r12,%rcx,8),%r8d  ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6aa27: mov    0x38(%r13,%r10,4),%ebx  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6aa2c: mov    0xc(%r12,%rbx,8),%ebx  ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6aa31: mov    0x3c(%r13,%r10,4),%edi  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6aa36: mov    0xc(%r12,%rdi,8),%ecx  ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6aa3b: mov    0x40(%r13,%r10,4),%edx  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6aa40: mov    0xc(%r12,%rdx,8),%edx  ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6aa45: mov    0x44(%r13,%r10,4),%esi  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6aa4a: mov    0xc(%r12,%rsi,8),%edi  ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6aa4f: mov    0x48(%r13,%r10,4),%ebp  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6aa54: mov    0xc(%r12,%rbp,8),%ebp  ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6aa59: mov    0x4c(%r13,%r10,4),%esi  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6aa5e: mov    0xc(%r12,%rsi,8),%esi  ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6aa63: add    0x4(%rsp),%eax
  0x00007f2130c6aa67: add    0x8(%rsp),%eax
  0x00007f2130c6aa6b: add    0xc(%rsp),%eax
  0x00007f2130c6aa6f: add    0x10(%rsp),%eax
  0x00007f2130c6aa73: add    0x14(%rsp),%eax
  0x00007f2130c6aa77: add    %r14d,%eax
  0x00007f2130c6aa7a: add    %r11d,%eax
  0x00007f2130c6aa7d: add    %r9d,%eax
  0x00007f2130c6aa80: add    %r8d,%eax
  0x00007f2130c6aa83: add    %ebx,%eax
  0x00007f2130c6aa85: add    %ecx,%eax
  0x00007f2130c6aa87: add    %edx,%eax
  0x00007f2130c6aa89: add    %edi,%eax
  0x00007f2130c6aa8b: add    %ebp,%eax
  0x00007f2130c6aa8d: add    %esi,%eax          ;*iadd {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@21 (line 22)

  0x00007f2130c6aa8f: add    $0x10,%r10d        ;*iinc {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@23 (line 21)

  0x00007f2130c6aa93: cmp    (%rsp),%r10d
  0x00007f2130c6aa97: jl     0x00007f2130c6a9a0  ;*if_icmpge {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@11 (line 21)

  0x00007f2130c6aa9d: mov    0xe8(%r15),%r11    ; ImmutableOopMap{r13=Oop }
                                                ;*goto {reexecute=1 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@26 (line 21)

  0x00007f2130c6aaa4: test   %eax,(%r11)        ;*goto {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@26 (line 21)
                                                ;   {poll}
  0x00007f2130c6aaa7: cmp    (%rsp),%r10d
  0x00007f2130c6aaab: jge    0x00007f2130c6aab9
  0x00007f2130c6aaad: vmovd  %xmm0,%esi
  0x00007f2130c6aab1: mov    (%rsp),%edi
  0x00007f2130c6aab4: jmpq   0x00007f2130c6a9a7
  0x00007f2130c6aab9: vmovd  %xmm0,%esi
  0x00007f2130c6aabd: cmp    %esi,%r10d
  0x00007f2130c6aac0: jge    0x00007f2130c6a985
  0x00007f2130c6aac6: xchg   %ax,%ax            ;*iload_1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@14 (line 22)

  0x00007f2130c6aac8: mov    0x10(%r13,%r10,4),%r8d  ;*aaload {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@17 (line 22)

  0x00007f2130c6aacd: add    0xc(%r12,%r8,8),%eax  ;*iadd {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@21 (line 22)
                                                ; implicit exception: dispatches to 0x00007f2130c6aaee
  0x00007f2130c6aad2: inc    %r10d              ;*iinc {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@23 (line 21)

  0x00007f2130c6aad5: cmp    %esi,%r10d
  0x00007f2130c6aad8: jl     0x00007f2130c6aac8  ;*if_icmpge {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@11 (line 21)

  0x00007f2130c6aada: jmpq   0x00007f2130c6a985
  0x00007f2130c6aadf: mov    $0xffffff86,%esi
  0x00007f2130c6aae4: xchg   %ax,%ax
  0x00007f2130c6aae7: callq  0x00007f2130c2bd80  ; ImmutableOopMap{rbp=NarrowOop }
                                                ;*iload_1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@14 (line 22)
                                                ;   {runtime_call UncommonTrapBlob}
  0x00007f2130c6aaec: ud2a                      ;*iload_1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@14 (line 22)

  0x00007f2130c6aaee: mov    $0xfffffff6,%esi
  0x00007f2130c6aaf3: callq  0x00007f2130c2bd80  ; ImmutableOopMap{}
                                                ;*getfield r1 {reexecute=1 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)
                                                ;   {runtime_call UncommonTrapBlob}
  0x00007f2130c6aaf8: ud2a                      ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)

  0x00007f2130c6aafa: mov    $0xfffffff6,%esi
  0x00007f2130c6aaff: callq  0x00007f2130c2bd80  ; ImmutableOopMap{}
                                                ;*arraylength {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@10 (line 21)
                                                ;   {runtime_call UncommonTrapBlob}
  0x00007f2130c6ab04: ud2a                      ;*getfield r1 {reexecute=0 rethrow=0 return_oop=0 return_vt=0}
                                                ; - Bench::testr@18 (line 22)

  0x00007f2130c6ab06: hlt    
[snip]
```

# Operations Inside the Interpreter

You may wonder -- if the `testv` and `testr` methods have the exact same bytecode, how does the interpreter handle the [aaload](https://docs.oracle.com/javase/specs/jvms/se8/html/jvms-6.html#jvms-6.5.aaload)
bytecode, which needs to operate on the two arrays that are laid out different?

You can see this in the [TemplateTable::aaload()](http://hg.openjdk.java.net/valhalla/valhalla/file/a5573f4f6392/src/hotspot/cpu/x86/templateTable_x86.cpp#l819)
handler of the interpreter:

```
  if (ValueArrayFlatten) {
    Label is_flat_array, done;
    __ test_flat_array_oop(array, rbx, is_flat_array);
    do_oop_load(_masm,
        Address(array, index,
                UseCompressedOops ? Address::times_4 : Address::times_ptr,
                arrayOopDesc::base_offset_in_bytes(T_OBJECT)),
         rax,
         IN_HEAP_ARRAY);
    __ jmp(done);
    __ bind(is_flat_array);
    __ call_VM(rax, CAST_FROM_FN_PTR(address,
          InterpreterRuntime::value_array_load), array, index);
    __ bind(done);

```

If the array is laid out as a 'flat' array, we will call InterpreterRuntime::value_array_load(),
which essentially allocates and returns a new wrapper object that contains all the fields of the
V object at the given array index.
