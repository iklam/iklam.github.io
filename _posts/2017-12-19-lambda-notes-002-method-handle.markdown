---
layout: post
title:  "Lambda Notes 2 - MethodHandle"
date:   2017-12-19 07:58:14 -0800
categories: jekyll update
---

# Hello MethodHandle

To understand what's happening with the extra-long parameter to `invokedynamic` from
[my last post]({% post_url 2017-12-14-lambda-notes-001 %}), let's take a detour in
[MethodHandle](https://docs.oracle.com/javase/8/docs/api/java/lang/invoke/MethodHandle.html).

(The main reason that I talk about MethodHandle here is to explain
the strange call stacks we will see when diving into Lambdas.)

```
$ cat HelloMH.java
import java.lang.invoke.*;
 
public class HelloMH {
    public static void main(String args[]) throws Throwable {
        MethodHandles.Lookup lookup = MethodHandles.lookup();
        MethodType mt = MethodType.methodType(void.class, String.class);
        MethodHandle mh = lookup.findStatic(HelloMH.class, "callme", mt);
        mh.invokeExact("yo!");
    }
 
    private static void callme(String x) {
        System.out.println("Hello MH.invoke: " + x);
        Thread.dumpStack();
    }
}
 
----

$ javac HelloMH.java
$ javap -c HelloMH.class

public class HelloMH {

 public HelloMH();
  Code:
   0: aload_0
   1: invokespecial #1    // java/lang/Object."<init>":()V
   4: return

 public static void main(java.lang.String[]) throws java.lang.Throwable;
  Code:
   0: invokestatic  #2    // java/lang/invoke/MethodHandles.lookup:()\
                          //   Ljava/lang/invoke/MethodHandles$Lookup;
   3: astore_1
   4: getstatic     #3    // java/lang/Void.TYPE:Ljava/lang/Class;
   7: ldc           #4    // class java/lang/String
   9: invokestatic  #5    // java/lang/invoke/MethodType.methodType:\
                          //   (Ljava/lang/Class;Ljava/lang/Class;)\
                          //    Ljava/lang/invoke/MethodType;
  12: astore_2
  13: aload_1
  14: ldc           #6    // class HelloMH
  16: ldc           #7    // String callme
  18: aload_2
  19: invokevirtual #8    // java/lang/invoke/MethodHandles$Lookup.findStatic:\
                          //   (Ljava/lang/Class;Ljava/lang/String;\
                          //    Ljava/lang/invoke/MethodType;)\
                          //    Ljava/lang/invoke/MethodHandle;
  22: astore_3
  23: aload_3
  24: ldc           #9    // String yo!
  26: invokevirtual #10   // java/lang/invoke/MethodHandle.invokeExact:\
                          //   (Ljava/lang/String;)V
  29: return
}
 
----
 
$ java -XX:+UnlockDiagnosticVMOptions -XX:+ShowHiddenFrames -cp . HelloMH
Hello MH.invoke: yo!
java.lang.Exception: Stack trace
	at java.base/java.lang.Thread.dumpStack(Thread.java:1435)
	at HelloMH.callme(HelloMH.java:13)
	at java.base/java.lang.invoke.DirectMethodHandle$Holder
               .invokeStatic(DirectMethodHandle$Holder:1000010)
	at java.base/java.lang.invoke.LambdaForm$MH/804611486
               .invokeExact_MT(LambdaForm$MH:1000019)
	at HelloMH.main(HelloMH.java:8)
```

# Compilation of MethodHandle.invokeExact by javac

[`MethodHandle.invokeExact`](https://docs.oracle.com/javase/9/docs/api/java/lang/invoke/MethodHandle.html#invokeExact-java.lang.Object...-)
look similar to
[`Method.invoke`](https://docs.oracle.com/javase/7/docs/api/java/lang/reflect/Method.html#invoke(java.lang.Object,%20java.lang.Object...))
in the [Java Reflection
API](https://docs.oracle.com/javase/8/docs/api/java/lang/reflect/package-summary.html). However,
it's compiled very differently by javac.

Even though the argument type of `MethodHandle.invokeExact` is
`void (java.lang.Object...)`, the bytecodes emitted by javac looks as
if you were calling a method with the signature `void
(java.lang.String)`.  This is explained in the section __Method handle
compilation__ in the [MethodHandle
reference](https://docs.oracle.com/javase/9/docs/api/java/lang/invoke/MethodHandle.html). You
can also see the reference to the [`@PolymorphicSignature`](http://hg.openjdk.java.net/jdk/hs/file/f43576cfb273/src/java.base/share/classes/java/lang/invoke/MethodHandle.java#l436) annotation
in the [`MethodHandle.invokeExact()`](
http://hg.openjdk.java.net/jdk/hs/file/f43576cfb273/src/java.base/share/classes/java/lang/invoke/MethodHandle.java#l485) source code:


```
$ javap java.lang.invoke.MethodHandle | grep invokeExact
  public final native java.lang.Object invokeExact(java.lang.Object...)
      throws java.lang.Throwable;
$ javap -private -c HelloMH.class
...
   23: aload_3            // local 3 is the <mh> variable
   24: ldc           #9   // String "yo!"
   26: invokevirtual #10  // Method java/lang/invoke/MethodHandle.invokeExact:\
                          //   (Ljava/lang/String;)V
...
```

# Execution of the MethodHandle.invokeExact

To see how `MethodHandle.invokeExact` actually calls the target method, let's look at the stack trace.
Even though the bytecode is `invokevirtual MethodHandle.invokeExact(...)`, the call frame for
`invokeExact` is missing in the call stack, and is magically replaced by a call to a dynamically
generated method `java.lang.invoke.LambdaForm$MH/804611486.invokeExact_MT()`.

So what's the magic here? You can see some
explanations in this [StackOverflow
answer](https://stackoverflow.com/questions/13978355/on-signature-polymorphic-methods-in-java-7) and this
[HotSpot blog page](https://wiki.openjdk.java.net/display/HotSpot/Method+handles+and+invokedynamic).


To see the contents of the generated classes, use `-Djava.lang.invoke.MethodHandle.DUMP_CLASS_FILES=true`:

```
$ java -Djava.lang.invoke.MethodHandle.DUMP_CLASS_FILES=true \
    -XX:+UnlockDiagnosticVMOptions -XX:+ShowHiddenFrames \
    -cp . HelloMH
<... snip...>
Hello MH.invoke: yo!
java.lang.Exception: Stack trace
	at java.base/java.lang.Thread.dumpStack(Thread.java:1435)
	at HelloMH.callme(HelloMH.java:13)
	at java.base/java.lang.invoke.DirectMethodHandle$Holder
               .invokeStatic(DirectMethodHandle$Holder:1000010)
	at java.base/java.lang.invoke.LambdaForm$MH000/2008017533
               .invokeExact_MT000_LLL_V(LambdaForm$MH000:1000019)
	at HelloMH.main(HelloMH.java:8)
```

Note that for ease of debugging, when you specify `-Djava.lang.invoke.MethodHandle.DUMP_CLASS_FILES=true`,
the names of the `LambdaForm$MH` class is changed to `LambdaForm$MH000`. Let's disassemble it:

```
$ jdis 'DUMP_CLASS_FILES/java/lang/invoke/LambdaForm$MH000.class'
package  java/lang/invoke;

super final class LambdaForm$MH000
    version 52:0
{

@+java/lang/invoke/LambdaForm$Hidden { }
@+java/lang/invoke/LambdaForm$Compiled { }
@+jdk/internal/vm/annotation/ForceInline { }
static Method invokeExact_MT000_LLL_V
    :"(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;)V"
    stack 2 locals 3
{
  aload_0;
  checkcast    class MethodHandle;
  dup;
  astore_0;
  aload_2;
  checkcast    class MethodType;
  invokestatic Method Invokers.checkExactType
            :"(Ljava/lang/invoke/MethodHandle;Ljava/lang/invoke/MethodType;)V";
  aload_0;
  invokestatic Method Invokers.checkCustomized
               :"(Ljava/lang/invoke/MethodHandle;)V";
  aload_0;
  aload_1;
  invokevirtual Method MethodHandle.invokeBasic
               :"(Ljava/lang/Object;)V";
  return;
}

static Method dummy:"()V"
    stack 1 locals 0
{
  ldc  String "MH.invokeExact_MT000_LLL_V=Lambda(a0:L,a1:L,a2:L)=>{\n\
        t3:V=Invokers.checkExactType(a0:L,a2:L);\n\
        t4:V=Invokers.checkCustomized(a0:L);\n\
        t5:V=MethodHandle.invokeBasic(a0:L,a1:L);void}";
  pop;
  return;
}
}
```

You can see that `invokeExact_MT000_LLL_V` first performs a few checks
on its parameters, and then calls
[`MethodHandle.invokeBasic`](http://hg.openjdk.java.net/jdk/hs/file/f43576cfb273/src/java.base/share/classes/java/lang/invoke/MethodHandle.java#l544). Well, `invokeBasic` is another `@PolymorphicSignature` method, and the call is
magically replaced by `DirectMethodHandle$Holder.invokeStatic`, which
is also a generated method (see comments
[here](http://hg.openjdk.java.net/jdk/hs/file/f43576cfb273/src/java.base/share/classes/java/lang/invoke/DirectMethodHandle.java#l805)).

You can see the contents of `DirectMethodHandle$Holder.invokeStatic` by doing this:

```
$ javap -c 'java.lang.invoke.DirectMethodHandle$Holder'
...
  static java.lang.Object invokeStatic(java.lang.Object, java.lang.Object);
  Code:
     0: aload_0
     1: invokestatic  #18    // Method java/lang/invoke/DirectMethodHandle.\
                     internalMemberName:(Ljava/lang/Object;)Ljava/lang/Object;
     4: astore_2
     5: aload_1
     6: aload_2
     7: checkcast     #20    // class java/lang/invoke/MemberName
    10: invokestatic  #288   // Method java/lang/invoke/MethodHandle.\
                      linkToStatic:(Ljava/lang/Object;\
                           Ljava/lang/invoke/MemberName;)Ljava/lang/Object;
    13: areturn
```

There are many dfferent overloaded variants of
`DirectMethodHandle$Holder.invokeStatic`, but in our example we are
calling the one listed above: it takes 2 parameters: the first is a
DirectMethodHandle, and the second is the string we're trying to pass
to `callme`.

As you can expect, the call to [`MethodHandle.linkToStatic`](http://hg.openjdk.java.net/jdk/hs/file/f43576cfb273/src/java.base/share/classes/java/lang/invoke/MethodHandle.java#l556) is yet again some magic inside the JVM. Basically, it's a native method that knows the invocation target's [`Method*`](http://hg.openjdk.java.net/jdk/hs/file/f43576cfb273/src/hotspot/share/oops/method.hpp). In our example, `linkToStatic` creates a call frame to execute the `callme` method. Note that `linkToStatic` itself doesn't appear in the stack trace -- it kinds of makes a tail call into `callme`.




# MethodHandle vs varargs

Also note that the arguments to `MethodHandle.invokeExact` are NOT passed using the Varargs
convention (unlike [java.lang.reflect.Method.invoke()](https://docs.oracle.com/javase/7/docs/api/java/lang/reflect/Method.html#invoke(java.lang.Object,%20java.lang.Object...))
which would create an Object array to collect the arguments, and thus would be slower
and creating lots of garbage.) Here's an example of varargs for comparison:


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