---
layout: post
title:  "Lambda Notes 2 - MethodHandle"
date:   2017-12-19 07:58:14 -0800
categories: jekyll update
---

# Hello MethodHandle

To understand what's happening with the extra-long parameter to `invokedynamic` from
[my last post]({% post_url 2017-12-14-lambda-notes-001 %}), let's take a detour in
[MethodHandle](https://docs.oracle.com/javase/10/docs/api/java/lang/invoke/MethodHandle.html).

The main reasons that I talk about MethodHandles here are:
* Their implementation is similar to, but not as messy as, Lambdas.
  So it will be like a practice run before dealing with the real thing.
* Lambda is implemented using MethodHandles, so let's first understand
  how the latter works.


```
$ cat HelloMH.java
import java.lang.invoke.*;

public class HelloMH {
    public static void main(String ...args) throws Throwable {
        MethodHandles.Lookup lookup = MethodHandles.lookup();
        MethodType mt = MethodType.methodType(void.class, float.class);
        MethodHandle mh = lookup.findStatic(HelloMH.class, "callme", mt);
        mh.invokeExact(4.0f);
    }
 
    private static void callme(float x) {
        System.out.println("Hello MH.invoke: " + x);
        Thread.dumpStack();
    }
}
 
----

$ javac HelloMH.java
$ javap -c HelloMH.class

public class HelloMH {
 ...
 public static void main(java.lang.String[]) throws java.lang.Throwable;
  Code:
   0: invokestatic  #2    // java/lang/invoke/MethodHandles.lookup:()\
                          //   Ljava/lang/invoke/MethodHandles$Lookup;
   3: astore_1
   4: getstatic     #3    // java/lang/Void.TYPE:Ljava/lang/Class;
   7: getstatic     #4    // Field java/lang/Float.TYPE:Ljava/lang/Class;

  10: invokestatic  #5    // java/lang/invoke/MethodType.methodType:\
                          //   (Ljava/lang/Class;Ljava/lang/Class;)\
                          //    Ljava/lang/invoke/MethodType;
  13: astore_2
  14: aload_1
  15: ldc           #6    // class HelloMH
  17: ldc           #7    // String callme
  19: aload_2
  20: invokevirtual #8    // java/lang/invoke/MethodHandles$Lookup.findStatic:\
                          //   (Ljava/lang/Class;Ljava/lang/String;\
                          //    Ljava/lang/invoke/MethodType;)\
                          //    Ljava/lang/invoke/MethodHandle;
  23: astore_3
  24: aload_3             // the MethodHandle -- 1st call parameter
  25: ldc           #9    // float 4.0f       -- 2nd call parameter
  26: invokevirtual #10   // java/lang/invoke/MethodHandle.invokeExact:\
                          //   (F)V
  30: return
}
 
----
 
$ java -XX:+UnlockDiagnosticVMOptions -XX:+ShowHiddenFrames -cp . HelloMH
Hello MH.invoke: 4.0
java.lang.Exception: Stack trace
    at java.base/java.lang.Thread.dumpStack(Thread.java:1434)
    at HelloMH.callme(HelloMH.java:13)
    at java.base/java.lang.invoke.LambdaForm$DMH/0x00000007c0060840\
       .invokeStatic(LambdaForm$DMH:1000010)
    at java.base/java.lang.invoke.LambdaForm$MH/0x00000007c0061040\
       .invokeExact_MT(LambdaForm$MH:1000019)
    at HelloMH.main(HelloMH.java:8)
```

<i>Note: The `/0x00000007c0061040` notation printed in the stack trace indicate that `LambdaForm$DMH`
and `LambdaForm$MH` are loaded as [JVM anonymous classes](https://blogs.oracle.com/jrose/anonymous-classes-in-the-vm)
(which are not to be confused by
[anonymous classes in the Java source code](https://docs.oracle.com/javase/tutorial/java/javaOO/anonymousclasses.html), ugh!).

<i>For breveity, I will omit such notations in the rest of this page.


# Compilation of MethodHandle.invokeExact by javac

[`MethodHandle.invokeExact`](https://docs.oracle.com/javase/10/docs/api/java/lang/invoke/MethodHandle.html#invokeExact-java.lang.Object...-)
looks similar to
[`Method.invoke`](https://docs.oracle.com/javase/7/docs/api/java/lang/reflect/Method.html#invoke(java.lang.Object,%20java.lang.Object...))
in the [Java Reflection
API](https://docs.oracle.com/javase/8/docs/api/java/lang/reflect/package-summary.html). However,
it's compiled very differently by javac.

Even though the argument type of `MethodHandle.invokeExact` is
`void (Object...)`, the bytecodes emitted by javac looks as
if you were calling the virtual method `void
MethodHandle.invokeExact(float)`, which doesn't exist!

```
$ javap java.lang.invoke.MethodHandle | grep invokeExact
  public final native java.lang.Object invokeExact(java.lang.Object...)
      throws java.lang.Throwable;
$ javap -private -c HelloMH.class
...
   23: aload_3            // local 3 is the <mh> variable
   24: ldc           #9   // float 4.0f
   26: invokevirtual #10  // Method java/lang/invoke/MethodHandle.invokeExact:\
                          //   (F)V
...
```

To understand what's happening, see the section __Method handle
compilation__ in the [MethodHandle
reference](https://docs.oracle.com/javase/10/docs/api/java/lang/invoke/MethodHandle.html). You
can also see the reference to the [`@PolymorphicSignature`](http://hg.openjdk.java.net/jdk/hs/file/f43576cfb273/src/java.base/share/classes/java/lang/invoke/MethodHandle.java#l436) annotation
in the [`MethodHandle.invokeExact()`](
http://hg.openjdk.java.net/jdk/hs/file/f43576cfb273/src/java.base/share/classes/java/lang/invoke/MethodHandle.java#l485) source code.


# Execution of MethodHandle.invokeExact

To see how `MethodHandle.invokeExact` actually calls the target method, let's look at the stack trace from above.
Even though the bytecode is `invokevirtual MethodHandle.invokeExact(...)`, the call frame for
`invokeExact` is missing in the call stack, and is magically replaced by a call to a dynamically
generated method `java.lang.invoke.LambdaForm$MH.invokeExact_MT()`.

To see the contents of the generated classes, use
`-Djava.lang.invoke.MethodHandle.DUMP_CLASS_FILES=true`. (Note that
for ease of debugging, when this flag is specified, the names of the
`LambdaForm$MH` class is changed to `LambdaForm$MH000`)

```
$ java -Djava.lang.invoke.MethodHandle.DUMP_CLASS_FILES=true \
    -XX:+UnlockDiagnosticVMOptions -XX:+ShowHiddenFrames \
    -cp . HelloMH
<... snip...>
Hello MH.invoke: 4.0
java.lang.Exception: Stack trace
    at java.base/java.lang.Thread.dumpStack(Thread.java:1434)
    at HelloMH.callme(HelloMH.java:13)
    at java.base/java.lang.invoke.LambdaForm$DMH000
       .invokeStatic000_LF_V()
    at java.base/java.lang.invoke.LambdaForm$MH000
       .invokeExact_MT000_LFL_V()
    at HelloMH.main(HelloMH.java:8)


$ jdis 'DUMP_CLASS_FILES/java/lang/invoke/LambdaForm$MH000.class'
package  java/lang/invoke;

super final class LambdaForm$MH000
    version 52:0
{
@+java/lang/invoke/LambdaForm$Hidden { }
@+java/lang/invoke/LambdaForm$Compiled { }
@+jdk/internal/vm/annotation/ForceInline { }
static Method invokeExact_MT000_LFL_V\
               :"(Ljava/lang/Object;FLjava/lang/Object;)V"
	stack 2 locals 3
{
  aload_0;
  checkcast     class MethodHandle;
  dup;
  astore_0;
  aload_2;
  checkcast     class MethodType;
  invokestatic  Method Invokers.checkExactType\
                :"(Ljava/lang/invoke/MethodHandle;\
                   Ljava/lang/invoke/MethodType;)V";
  aload_0;
  invokestatic  Method Invokers.checkCustomized\
                :"(Ljava/lang/invoke/MethodHandle;)V";
  aload_0;
  fload_1;
  invokevirtual  Method MethodHandle.invokeBasic:"(F)V";
  return;
}

static Method dummy:"()V"
  stack 1 locals 0
{
  ldc  String "MH.invokeExact_MT000_LFL_V=Lambda(a0:L,a1:F,a2:L)=>{\n\
         t3:V=Invokers.checkExactType(a0:L,a2:L);\n\
         t4:V=Invokers.checkCustomized(a0:L);\n\
         t5:V=MethodHandle.invokeBasic(a0:L,a1:F);void}";
  pop;
  return;
}
}
```

You can see that `invokeExact_MT000_LFL_V` first performs a few checks
on its parameters, and then calls
[`MethodHandle.invokeBasic`](http://hg.openjdk.java.net/jdk/hs/file/f43576cfb273/src/java.base/share/classes/java/lang/invoke/MethodHandle.java#l544). Well, `invokeBasic` is another `@PolymorphicSignature` method, and the call is
again magically replaced by `LambdaForm$DMH000.invokeStatic000_LF_V`:

```
$ jdis 'DUMP_CLASS_FILES/java/lang/invoke/LambdaForm$DMH000.class'
...
static Method invokeStatic000_LF_V:"(Ljava/lang/Object;F)V"
    stack 2 locals 3
{
    aload_0;
    invokestatic    Method DirectMethodHandle.internalMemberName\
                       :"(Ljava/lang/Object;)Ljava/lang/Object;";
    astore_2;
    fload_1;
    aload_2;
    checkcast       class MemberName;
    invokestatic    Method MethodHandle.linkToStatic\
                        :"(FLjava/lang/invoke/MemberName;)V";
    return;
}
```

As you can expect, the call to [`MethodHandle.linkToStatic`](http://hg.openjdk.java.net/jdk/hs/file/f43576cfb273/src/java.base/share/classes/java/lang/invoke/MethodHandle.java#l556) is yet again some magic inside the JVM. Basically, it's a native method that knows the invocation target's [`Method*`](http://hg.openjdk.java.net/jdk/hs/file/f43576cfb273/src/hotspot/share/oops/method.hpp). In our example, `linkToStatic` creates a call frame to execute the `callme` method. Note that `linkToStatic` itself doesn't appear in the stack trace -- it kinds of makes a [tail call](https://en.wikipedia.org/wiki/Tail_call) into `callme`.

*References: if you're interested in more details, see this [StackOverflow answer](https://stackoverflow.com/questions/13978355/on-signature-polymorphic-methods-in-java-7) and 
this [HotSpot blog page](https://wiki.openjdk.java.net/display/HotSpot/Method+handles+and+invokedynamic).*


# Shuffling of Parameters

Our target method has a single declared parameter, a `float`, or `F` in the
method signatures. However, you can see that some extra parameters are
adding before and after the formal parameters:

  * The frame of `invokeExact_MT000_LFL_V` contains:
    * an object before the `F`: this is the MethodHandle `this` instance, which
      gets pushed to the frame because we're making a virtual call on a MethodHandle object.
    * an object after the `F`: this is the `MethodType`. It's appended by the `invokehandle`
      bytecode so we can dynamically check that we are invoking a MethodHandle of the
      expected type.
      
      This dynamic check is actually necessary because you can actually write valid Java source
      code like this which can only be checked at run time:
      ```
      import java.lang.invoke.*;
      public class BadMH {
        public static void main(String ...args) throws Throwable {
          MethodHandle mh[] = new MethodHandle[2];
          MethodHandles.Lookup lookup = MethodHandles.lookup();
          MethodType mt0 = MethodType.methodType(void.class, float.class);
          mh[0] = lookup.findStatic(BadMH.class, "callme", mt0);
          MethodType mt1 = MethodType.methodType(void.class, Object.class);
          mh[1] = lookup.findStatic(BadMH.class, "callme", mt1);
          for (MethodHandle x : mh) {
            x.invokeExact(4.0f);
         }
        }

        private static void callme(float x) {
          System.out.println("Hello MH.invoke: " + x);
        }
        private static void callme(Object x) {
          System.out.println("Hello MH.invoke: " + x);
        }
      }
      $ java -cp . BadMH
      Hello MH.invoke: 4.0
      java.lang.invoke.WrongMethodTypeException:
            expected (Object)void but found (float)void
        at java.lang.invoke.Invokers.newWrongMethodTypeException\
           (Invokers.java:476)
        at java.lang.invoke.Invokers.checkExactType(Invokers.java:485)
        at BadMH.main(BadMH.java:12)
    ```
  * The frame of `invokeStatic000_LF_V` contains:
    * an object before the `F`: this is the `MemberName` that represents the target method (it basically carries a [C++
      `Method` pointer](http://hg.openjdk.java.net/jdk/hs/file/f43576cfb273/src/hotspot/share/oops/method.hpp#l65) to
      the target method).

Inside `invokeStatic000_LF_V`, we shuffle the parameters such that the incoming call frame of `MethodHandle.linkToStatic` contains:

  * all the parameters as declared by the target method (a single `F` in our example)
  * followed by the `MemberName` of the target method.

When the native method `MethodHandle.linkToStatic` is entered, the "front" part of the call
stack already contains the exact parameters as needed by the target method.
`linkToStatic` simply retrieves the JVM `Method` pointer from the MemberName, drops
this last parameter, and jumps to the entry of the target method.

(We'll see this in more details in the *Linking Polymorphic Methods* sections below.)


# MethodHandle vs varargs

As we saw above, the arguments to `MethodHandle.invokeExact` are __not__ passed using the Varargs
convention (unlike [java.lang.reflect.Method.invoke](https://docs.oracle.com/javase/7/docs/api/java/lang/reflect/Method.html#invoke(java.lang.Object,%20java.lang.Object...))
which is Varargs and would create an Object array to collect the arguments, and thus would be slower
and creat lots of garbage.) Here's an example of varargs for comparison:


```
public class HelloVarargs {
    public static void main(String... args) {
        if (args.length == 0) {
            main("a", "b"); // compiled as:
                            //     main(new String[] {"a", "b"});
        }
    }
}
---
$ javap -c HelloVarargs.class
...
  public static void main(java.lang.String...);
    Code:
       0: aload_0
       1: arraylength
       2: ifne          22
       5: iconst_2
       6: anewarray     #2  // class java/lang/String
          ^^^^^^^ create a String array of 2 elements

       9: dup
      10: iconst_0
      11: ldc           #3  // String a
      13: aastore
      14: dup
      15: iconst_1
      16: ldc           #4  // String b
      18: aastore
      19: invokestatic  #5  // Method main:([Ljava/lang/String;)V
      22: return
```

# Benchmarking MethodHandles

Here's a benchmark of `java.lang.invoke.MethodHandle` vs `java.lang.reflect.Method`:

``` java
$ cat BenchMH.java
import java.lang.invoke.*;
import java.lang.reflect.*;
 
public class BenchMH {
  volatile static String c;
 
  public static void main(String args[]) throws Throwable {
    int loops = 100 * 1000 * 1000;
    try {
      loops = Integer.parseInt(args[0]);
    } catch (Throwable t) {}
 
    MethodHandles.Lookup lookup = MethodHandles.lookup();
    MethodType mt = MethodType.methodType(void.class, String.class);
    MethodHandle mh = lookup.findStatic(BenchMH.class, "callme", mt);
 
    Class[] argTypes = new Class[] { String.class };
    Method m = BenchMH.class.getDeclaredMethod("callme", argTypes);

    // Run the loop twice to discount start-up overhead
    for (int x=0; x<2; x++) {
      {
        long start = System.currentTimeMillis();
        loopMH(loops, mh);
        long end = System.currentTimeMillis();
        System.out.println("MH:    loops = " + loops + ": elapsed = " +
                           (end - start) + " ms");
      }
      {
        long start = System.currentTimeMillis();
        loopReflect(loops/100, m);
        long end = System.currentTimeMillis();
        System.out.println("Reflect: loops = " + (loops/100) + ": elapsed = " +
                           (end - start) + " ms");
      }
      {
        long start = System.currentTimeMillis();
        loopDirect(loops);
        long end = System.currentTimeMillis();
        System.out.println("direct:  loops = " + loops + ": elapsed = " +
                           (end - start) + " ms");
      }
    }
  }
 
  private static void loopMH(int loops, MethodHandle mh) throws Throwable {
    for (int i=0; i<loops; i++) {
      mh.invokeExact("yo!");
    }
  }
 
  private static void loopReflect(int loops, Method method) throws Throwable {
    for (int i=0; i<loops; i++) {
      method.invoke(null, "yo!");
    }
  }
 
 
  private static void loopDirect(int loops) {
    for (int i=0; i<loops; i++) {
      callme("yo!");
    }
  }
 
  private static void callme(String x) {
    c = x;
  }
}
 
$ java -XX:-Inline BenchMH 100000000

           LOOPS     ELAPSED   NORMALIZED
MH:      100000000   2333 ms     2333 ms
Reflect:   1000000   1023 ms   102300 ms  ... 43x slower than MH
direct:  100000000    972 ms      972 ms

$ java BenchMH 100000000

           LOOPS     ELAPSED   NORMALIZED
MH:      100000000   1073 ms     1073 ms
Reflect:   1000000    112 ms    11200 ms  ... 10x slower than MH
direct:  100000000    746 ms      746 ms
```

So you can see that, with inlining by the JIT compiler, `MethodHandle`
is more than 10x faster than reflection, and can almost match the speed
of a "real" method invocation (1073 ms vs 746 ms).

# Linking Polymorphic Methods in the HotSpot JVM (static invocations)

Let's look at the easy ones first. A few native polymorphic methods
(declared with the `@PolymorphicSignature` annotation) in the `MethodHandle` class
are invoked statically by the generated MethodHandle invoker classes:
  
  * invokeGeneric
  * invokeBasic
  * linkToVirtual
  * [`linkToStatic`](http://hg.openjdk.java.net/jdk/hs/file/f43576cfb273/src/java.base/share/classes/java/lang/invoke/MethodHandle.java#l563)
  * linkToSpecial
  * linkToInterface

Here's an example we have seen above:


```
static Method invokeStatic000_LF_V:"(Ljava/lang/Object;F)V"
  ...
  invokestatic MethodHandle.linkToStatic:"(FLjava/lang/invoke/MemberName;)V";

```

These calls are resolved and linked conventionally just like other
native static methods. The only interesting part is these methods are
implemented using assembler code, so you won't see a C function for
`Java_java_lang_invoke_MethodHandle_linkToStatic` inside libjava.so.


On x64, the imterpreter's implementation of `MethodHandle.linkToStatic` is
generated around here in [`MethodHandles::generate_method_handle_interpreter_entry`](http://hg.openjdk.java.net/jdk/hs/file/d6893a76c554/src/hotspot/cpu/x86/methodHandles_x86.cpp#l280). It
contains only 10 instructions:


```
(gdb) x/10i 0x7fffd8e5a920
   // pop(rax_temp)   --  return address
   0x7fffd8e5a920: 	pop    %rax
   // pop(rbx_member) --  extract last argument (MemberName)
   0x7fffd8e5a921:	pop    %rbx
   // push(rax_temp)  -- re-push return address
   0x7fffd8e5a922:	push   %rax

   // load_heap_oop(rbx_method, member_vmtarget)
   0x7fffd8e5a923:	mov    0x24(%rbx),%ebx
   0x7fffd8e5a926:	shl    $0x3,%rbx        // decode compressed oop

   // movptr(rbx_method, vmtarget_method);
   0x7fffd8e5a92a:	mov    0x10(%rbx),%rbx

   // testptr(rbx, rbx); jcc(Assembler::zero, L_no_such_method);
   0x7fffd8e5a92e:	test   %rbx,%rbx
   0x7fffd8e5a931:	je     0x7fffd8e5a93a    // Lno_such_method

   // jmp(Address(method, entry_offset));
   0x7fffd8e5a937:	jmpq   *0x48(%rbx)

   // bind(L_no_such_method);
   // jump(RuntimeAddress(StubRoutines::throw_AbstractMethodError_entry()));
   0x7fffd8e5a93a:	jmpq   0x7fffd8e5a280
```

As discussed previously, `linkToStatic` simply pops off the last parameter as a `MemberName`,
such that the incoming parameters are exactly what the target method wants, and then branch
to the target method (as a tail call).

# Linking Polymorphic Methods in the HotSpot JVM (Virtual Invocations)

Vitrual invocations (using the `invokevirtual` or `invokespecial` bytecodes)
of polymorphic methods are much more complicated, and involve lots of Java code.

Recall that a polymorphic method such as `MethodHandle.invokeExact` is compiled by javac into the
following bytecodes inside the classfile.

```
  23: aload_3             // the MethodHandle -- 1st call parameter
  24: ldc           #9    // String yo!       -- 2nd call parameter
  26: invokevirtual #10   // java/lang/invoke/MethodHandle.invokeExact:\
                          //   (Ljava/lang/String;)V
```

When the classfile is loaded by HotSpot, the `invokevirtual` bytecode is rewritten into the internal
`invokehandle` bytecode in here:

<pre>
->  (*opc) = (u1)Bytecodes::_invokehandle;

(gdb) where
#0 <a href="http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/interpreter/rewriter.cpp#l240">Rewriter::maybe_rewrite_invokehandle()</a>    @ rewriter.cpp:240
#1 <a href="http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/interpreter/rewriter.cpp#l174">Rewriter::rewrite_member_reference()</a>      @ rewriter.cpp:174
#2 <a href="http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/interpreter/rewriter.cpp#l472">Rewriter::scan_method()</a>                   @ rewriter.cpp:472
#3 <a href="http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/interpreter/rewriter.cpp#l550">Rewriter::rewrite_bytecodes()</a>             @ rewriter.cpp:550
#4 <a href="http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/interpreter/rewriter.cpp#l590">Rewriter::Rewriter()</a>                      @ rewriter.cpp:590
#5 <a href="http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/interpreter/rewriter.cpp#l572">Rewriter::rewrite()</a>                       @ rewriter.cpp:572
#6 <a href="http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/oops/instanceKlass.cpp#l655">InstanceKlass::rewrite_class()</a>            @ instanceKlass.cpp:655
#7 <a href="http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/oops/instanceKlass.cpp#l605">InstanceKlass::link_class_impl()</a>          @ instanceKlass.cpp:605
...
</pre>


When the `invokehandle` bytecode is executed for the first time, it's linked here by
calling back into Java.

<pre>
    // call java.lang.invoke.MethodHandleNatives::linkMethod(... String,
    //              MethodType) -> MemberName
    JavaCallArguments args;
    args.push_oop(Handle(THREAD, accessing_klass->java_mirror()));
    args.push_int(ref_kind);
    args.push_oop(Handle(THREAD, klass->java_mirror()));
    args.push_oop(name_str);
    args.push_oop(method_type);
    args.push_oop(appendix_box);
    JavaValue result(T_OBJECT);
->  JavaCalls::call_static(&result,
                           SystemDictionary::MethodHandleNatives_klass(),
                           vmSymbols::linkMethod_name(),
                           vmSymbols::linkMethod_signature(),
                           &args, CHECK_(empty));

(gdb) where
#0 <a href="http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/classfile/systemDictionary.cpp#l2556">SystemDictionary::find_method_handle_invoker()</a> @ systemDictionary.cpp:2556
#1 <a href="http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/interpreter/linkResolver.cpp#l519">LinkResolver::lookup_polymorphic_method()</a>      @ linkResolver.cpp:519
#2 <a href="http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/interpreter/linkResolver.cpp#l1661">LinkResolver::resolve_handle_call()</a>            @ linkResolver.cpp:1661
#3 <a href="http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/interpreter/linkResolver.cpp#l1647">LinkResolver::resolve_invokehandle()</a>           @ linkResolver.cpp:1647
#4 <a href="http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/interpreter/linkResolver.cpp#l1573">LinkResolver::resolve_invoke()</a>                 @ linkResolver.cpp:1573
#5 <a href="http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/interpreter/interpreterRuntime.cpp#l968">InterpreterRuntime::resolve_invokehandle()</a>     @ interpreterRuntime.cpp:968
#6 <a href="http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/interpreter/interpreterRuntime.cpp#l1016">InterpreterRuntime::resolve_from_cache()</a>       @ interpreterRuntime.cpp:1016
</pre>

When the `MethodHandleNatives.linkMethod` call completes, a [`MemberName`](http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/java.base/share/classes/java/lang/invoke/MemberName.java) is returned ([see here](http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/classfile/systemDictionary.cpp#l2557)).

  * The `MemberName` gets decomposed by [`unpack_method_and_appendix`](http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/classfile/systemDictionary.cpp#l2488),
  * then the information is stored into a CallInfo using [`CallInfo::set_handle`](http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/interpreter/linkResolver.cpp#l102),
  * and the information is finally stored into the constant pool via [`ConstantPoolCacheEntry::set_method_handle`](http://hg.openjdk.java.net/jdk/hs/file/7f5fca094057/src/hotspot/share/oop/cpCache.cpp#l301)

At this point, the linking of this polymorphic method call is complete. Subsequently, this `invokehandle`
bytecode can be executed by loading information about the MethodHandle from the corresponding  `ConstantPoolCacheEntry`.

# TODO ...

I can probably include more details here, but I'll skip them for now ...

<!------


MethodHandles::generate_method_handle_dispatch (_masm=0x7ffff000eb90, iid=vmIntrinsics::_invokeBasic, 
    receiver_reg=0x1, member_reg=0xffffffffffffffff, for_compiler_entry=false)
    at /home/iklam/jdk/blu/open/src/hotspot/cpu/x86/methodHandles_x86.cpp:295


  __ load_heap_oop(method_temp, Address(recv, NONZERO(java_lang_invoke_MethodHandle::form_offset_in_bytes())));
   0x7fffd8e6592c:	mov    0x14(%rcx),%ebx
   0x7fffd8e6592f:	shl    $0x3,%rbx

  __ load_heap_oop(method_temp, Address(method_temp, NONZERO(java_lang_invoke_LambdaForm::vmentry_offset_in_bytes())));
   0x7fffd8e65933:	mov    0x28(%rbx),%ebx
   0x7fffd8e65936:	shl    $0x3,%rbx

  __ load_heap_oop(method_temp, Address(method_temp, NONZERO(java_lang_invoke_MemberName::method_offset_in_bytes())));
   0x7fffd8e6593a:	mov    0x24(%rbx),%ebx
   0x7fffd8e6593d:	shl    $0x3,%rbx

  __ movptr(method_temp, Address(method_temp, NONZERO(java_lang_invoke_ResolvedMethodName::vmtarget_offset_in_bytes())));
   0x7fffd8e65941:	mov    0x10(%rbx),%rbx

   MethodHandles::jump_from_method_handle()

   __ testptr(rbx, rbx);
   0x7fffd8e65945:	test   %rbx,%rbx
   __ jcc(Assembler::zero, L_no_such_method);
   0x7fffd8e65948:	je     0x7fffd8e65951

  __ jmp(Address(method, entry_offset));
   0x7fffd8e6594e:	jmpq   *0x48(%rbx)

  __ bind(L_no_such_method);
   0x7fffd8e65951:	jmpq   0x7fffd8e65300



Method::make_method_handle_intrinsic() ....


Invokers.methodHandleInvokeLinkerMethod


InvokerBytecodeGenerator.loadAndInitializeInvokerClass(byte[], Object[]) line: 295  
InvokerBytecodeGenerator.loadMethod(byte[]) line: 287  
InvokerBytecodeGenerator.generateCustomizedCode(LambdaForm, MethodType) line: 692  
LambdaForm.compileToBytecode() line: 870  
Invokers.invokeHandleForm(MethodType, boolean, int) line: 333  
Invokers.methodHandleInvokeLinkerMethod(String, MethodType, Object[]) line: 238  
MethodHandleNatives.linkMethodImpl(Class<?>, int, Class<?>, String, Object, Object[]) line: 459  
MethodHandleNatives.linkMethod(Class<?>, int, Class<?>, String, Object, Object[]) line: 450  
HelloWorld.main(String[]) line: 10  

=> Same type of invoke in the same holder class reuses the invoker (anonymous class is loaded only once). E.g.,
        MethodHandle mh = lookup.findStatic(HelloWorld.class, "callme", mt);
        mh.invokeExact(1);
        mh.invokeExact(1);

--->


# Summary

Now you know how a MethodHandle is invoked. In the next blog entry, we'll see how MethodHandles are used by the `invokedynamic` bytecode.
