---
layout: post
title:  "Lambda Notes 4 - Creation of Lambdas"
date:   2018-09-21 07:58:14 -0800
categories: jekyll update
---

Let's go back to a very simple program that creates a non-capturing Lambda:

```
public class NonCapLamb {
    public static void main(String[] args) {
        Runnable t = () -> {System.out.println("Duh");};
        t.run();
    }
}
```

```
$ jdis NonCapLamb.class
...
public static Method main:"([Ljava/lang/String;)V"
  stack 1 locals 2
{
  invokedynamic  InvokeDynamic REF_invokeStatic:\
      java/lang/invoke/LambdaMetafactory.metafactory:\
          "(Ljava/lang/invoke/MethodHandles$Lookup;\
            Ljava/lang/String;\
            Ljava/lang/invoke/MethodType;\
            Ljava/lang/invoke/MethodType;\
            Ljava/lang/invoke/MethodHandle;\
            Ljava/lang/invoke/MethodType;
           )Ljava/lang/invoke/CallSite;":\
            run:\
               "()Ljava/lang/Runnable;"\
               MethodType "()V", \
               MethodHandle REF_invokeStatic:NonCapLamb.lambda$main$0:"()V", \
               MethodType "()V";

  astore_1;
  aload_1;
  invokeinterface	InterfaceMethod java/lang/Runnable.run:"()V",  1;
  return;
}

private static synthetic Method lambda$main$0:"()V"
  stack 2 locals 0
{
  getstatic	Field java/lang/System.out:"Ljava/io/PrintStream;";
  ldc	        String "Duh";
  invokevirtual	Method java/io/PrintStream.println:"(Ljava/lang/String;)V";
  return;
}
...
```

We will skip the discussion on the bootstrap method [LambdaMetafactory.metafactory](http://hg.openjdk.java.net/jdk/jdk/file/2a51125b2794/src/java.base/share/classes/java/lang/invoke/LambdaMetafactory.java#l316), which is in itself another long story. In this blog, we'll just look at what happens inside HotSpot.

Let's first find out what the `CONSTANT_InvokeDynamic` entry is
resolved to. This can be done with a __debug build__ of the JVM using
the following parameters:

```
$ java -XX:+TraceInvokeDynamic \
    -Djdk.internal.lambda.dumpProxyClasses=DUMP_CLASS_FILES \
    -Djava.lang.invoke.MethodHandle.DUMP_CLASS_FILES=true \
    -cp . NonCapLamb
[....]

set_method_handle bc=186 appendix=0x0000000451064ea8 method_type=0x0000000451056c08 method=0x00000008001fdaf0 
{method}
 - method holder:     'java/lang/invoke/Invokers$Holder'
 - constants:         0x00000008007d4f78 constant pool [110] {0x00000008007d4f78} for 'java/lang/invoke/Invokers$Holder' cache=0x00000008001fd510
 - access:            0x8  static 
 - name:              'linkToTargetMethod'
 - signature:         '(Ljava/lang/Object;)Ljava/lang/Object;'
 ...
java.lang.invoke.BoundMethodHandle$Species_L 
{0x0000000451064ea8} - klass: 'java/lang/invoke/BoundMethodHandle$Species_L'
 - ---- fields (total size 4 words):
 - 'customizationCount' 'B' @12  0
 - private final 'type' 'Ljava/lang/invoke/MethodType;' @16  a 'java/lang/invoke/MethodType'{0x0000000451056c08} = ()Ljava/lang/Runnable; (8a20ad81)
 - final 'form' 'Ljava/lang/invoke/LambdaForm;' @20  a 'java/lang/invoke/LambdaForm'{0x0000000451064e10} => a 'java/lang/invoke/MemberName'{0x00000004510694e0} = {method} {0x00007f530f8fe618} 'invoke000_L_L' '(Ljava/lang/Object;)Ljava/lang/Object;' in 'java/lang/invoke/LambdaForm$MH000' (8a20c9c2)
 - 'asTypeCache' 'Ljava/lang/invoke/MethodHandle;' @24  NULL
 (0)
 - final 'argL0' 'Ljava/lang/Object;' @28  a 'NonCapLamb$$Lambda$1'{0x0000000451060a68} (8a20c14d)
```

Note that `-XX:+TraceInvokeDynamic` produces a lot of outputs for the
above command-line, but there's only a single output for
`set_method_handle bc=186`, where `186` is the `invokedynamic`
bytecode. So this must be the output for the `invokedynamic` bytecode
in `NonCapLamb.main`.

*(All the other outputs are for `bc=233`, which is the `invokehandle`
bytecode. These aren't immediately relevant to our discussion here, so
let's ignore them for now. You can read more about them in [my blog on MethodHandles]({% post_url 2017-12-19-lambda-notes-002-method-handle %}))*

We also dynamically generated a couple of classes *(this is with the [current jdk/jdk repo as of 2018/09/21](http://hg.openjdk.java.net/jdk/jdk/rev/46ca82c15f6c). Older JDKs have many more generated classes.)*

```
$ find DUMP_CLASS_FILES/ -type f
DUMP_CLASS_FILES/java/lang/invoke/LambdaForm$MH000.class
DUMP_CLASS_FILES/NonCapLamb$$Lambda$1.class
```

From the `-XX:+TraceInvokeDynamic` output, this `CONSTANT_InvokeDynamic` entry is resolved to have

  * `adapter` = the method `java/lang/invoke/Invokers$Holder::linkToTargetMethod:(Ljava/lang/Object;)Ljava/lang/Object;`
  * `appendix` = an instance of `java/lang/invoke/BoundMethodHandle$Species_L`

Recall from [previous blog post]({%
post_url 2017-12-20-lambda-notes-003-invoke-dynamic %}) that after the constant pool
resolution, the `invokedynamic` bytecode calls a method like this:

```
adapter(xxx parameters, appendix);
```

In our example here, the xxx parameters are empty, so it essentially calls

```
BoundMethodHandle$Species_L myMH = <get appendix from the cpCache entry>
java/lang/invoke/Invokers$Holder::linkToTargetMethod(myMH)
```

The Invokers$Holder class is not defined in the source code of [Invokers.java](http://hg.openjdk.java.net/jdk/jdk/file/2a51125b2794/src/java.base/share/classes/java/lang/invoke/Invokers.java#l655) but rather generated during the JDK build process (stored in the file `$JAVA_HOME/lib/modules`). We can see its contents:

```
$ javap -c 'java/lang/invoke/Invokers$Holder'
[... snip ...]
static java.lang.Object linkToTargetMethod(java.lang.Object);
  0: aload_0
  1: checkcast     #14 // class java/lang/invoke/MethodHandle
  4: invokevirtual #77 // Method java/lang/invoke/MethodHandle.\
                           invokeBasic:()Ljava/lang/Object;
  7: areturn
```

Translated back to Java code:

```
class java/lang/invoke/Invokers$Holder {
    Object linkToTargetMethod(Object myMH) {
        return ((MethodHandle)myMH).invokeBasic();
    }
}

```

where `myMH` conatins the following fields (simplified from the `TraceInvokeDynamic` output from above:

```
- form  : java/lang/invoke/LambdaForm$MH000::invoke000_L_L
- argL0 : an instance of 'NonCapLamb$$Lambda$1'{0x0000000451060a68}

```

As mentioned in [my blog on MethodHandles]({% post_url 2017-12-19-lambda-notes-002-method-handle %}), the `invokeBasic` call causes this method to be called


```
LambdaForm$MH000.invoke000_L_L(myMH)
```

Let's look at the generated class `LambdaForm$MH000`:

```
$ javap -c 'DUMP_CLASS_FILES/java/lang/invoke/LambdaForm$MH000.class'
final class java.lang.invoke.LambdaForm$MH000 {
  static java.lang.Object invoke000_L_L(java.lang.Object);
  0: aload_0
  1: checkcast     #14  // class java/lang/invoke/BoundMethodHandle$Species_L
  4: getfield      #18  // Field java/lang/invoke/BoundMethodHandle$Species_L.
                              argL0:Ljava/lang/Object;
  7: areturn
}
```

So it essentially just returns `myMH.argL0`, which is an instance of this class:

```
$ javap -c 'DUMP_CLASS_FILES/NonCapLamb$$Lambda$1.class'
final class NonCapLamb$$Lambda$1 implements java.lang.Runnable {
  public void run();
  0: invokestatic  #17    // Method NonCapLamb.lambda$main$0:()V
  3: return
}
```

So, we essentially executed the following Java code:

```
public class NonCapLamb {
    public static void main(String[] args) {
      //Runnable t = () -> {System.out.println("Duh");};
        Runnable t = (new BoundMethodHandle$Species_L()).argL0;
        t.run();
    }

    void lambda$main$0() {
         System.out.println("Duh");
    }

    class $$Lambda$1 {
        public void run() {
           lambda$main$0();
        }
    }
}

class BoundMethodHandle$Species_L {
   Runnable argL0 = new NonCapLamb$$Lambda$1();
}
```


A long story cut short, that's how you do Lambda :-)
