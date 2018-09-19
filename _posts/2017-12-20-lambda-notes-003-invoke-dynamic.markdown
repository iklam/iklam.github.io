---
layout: post
title:  "Lambda Notes 3 - InvokeDynamic"
date:   2017-12-20 07:58:14 -0800
categories: jekyll update
---

*(Last updated Sep 2, 2018)*

# Hello InvokeDynamic

Finally, we're ready to use an `invokedynamic` bytecode.

Since we can't generate arbitrary `invokedynamic` bytecodes using Java
source code, we have to write a Java assembler file. The tools like
`jdis` and `jasm` are described by my [previous blog post]({%
post_url 2017-12-14-lambda-notes-001 %}).


(HelloInvoker.jasm in the listing below has manual line breaks so it can't be compiled by `jasm`. Here's 
[a compilable HelloInvoker.jasm]({{ site.url }}/examples/HelloInvoker.jasm.txt)).

```
// HelloInvoke.java
import java.lang.invoke.*;
 
public class HelloInvoke {
    public static void main(String args[]) throws Throwable {
        HelloInvoker.doit();
    }
 
    static CallSite myBSM(MethodHandles.Lookup lookup,
           String name, MethodType type) throws Throwable {
        MethodType mt = MethodType.methodType(void.class, String.class);
        MethodHandle mh = lookup.findStatic(HelloInvoke.class, name, mt);
        return new ConstantCallSite(mh.asType(type));
    }
 
    static void callme(String x) {
        System.out.println("Hello invokedynamic: " + x);
    }
}

// HelloInvoker.jasm
super public class HelloInvoker
    version 52:0
{
    public static Method doit:"()V"
    stack 3 locals 1
    {
     ldc           String "yippee!";
     invokedynamic InvokeDynamic REF_invokeStatic:\
            HelloInvoke.myBSM:\
                "(Ljava/lang/invoke/MethodHandles$Lookup;\
                  Ljava/lang/String;\
                  Ljava/lang/invoke/MethodType;\
                 )Ljava/lang/invoke/CallSite;"\
              :callme:\
                 "(Ljava/lang/String;)V";
     return;
    }
}
 
----
$ jasm HelloInvoker.jasm
$ javac HelloInvoke.java
$ java -cp . HelloInvoke
Hello invokedynamic: yippee!
```

# Bootstrap Method

As seen in InvokeInvoker.jasm, the `invokedynamic` bytecode uses a
[CONSTANT_InvokeDynamic](https://docs.oracle.com/javase/specs/jvms/se7/html/jvms-4.html#jvms-4.4.10) entry in the constant pool.
The [full specification](https://docs.oracle.com/javase/specs/jvms/se7/html/jvms-4.html#jvms-4.4.10) is pretty
complicated, but in simple usage, we just need the following parts:

  * `reference_kind` -- here we use `REF_invokeStatic`
  * the [bootstrap method](https://docs.oracle.com/javase/specs/jvms/se7/html/jvms-4.html#jvms-4.7.21).
  * parameters to the bootstrap method

In our example, the bootstrap method is specified here:

```
    HelloInvoke.myBSM:\
         "(Ljava/lang/invoke/MethodHandles$Lookup;\
           Ljava/lang/String;\
           Ljava/lang/invoke/MethodType;\
          )Ljava/lang/invoke/CallSite;"
```

You can see that its name and parameter types corresponds to the method:

```
CallSite HelloInvoke.myBSM(
           MethodHandles.Lookup caller,
           String name,
           MethodType type)
```


The first 3 parameters of the bootstrap method must be exactly as showned above.
It's possible to pass additional parameters to the bootstrap method, as we will see later when looking at Lambda functions.

When the bootstrap method is called:

  * the `caller` parameter is provided by the JVM
  * the `name` parameter is extracted from the constant pool entry. It indicates the method you want to invoke. (In our example, it is `"callme"`)
  * the `type` parameter is also extracted from the constant pool entry. It indicates the parameter- and return types of the method that you want to invoke. In our case, it is `"(Ljava/lang/String;)V"`


The bootstrap method must return an object of the
[`CallSite`](https://docs.oracle.com/javase/9/docs/api/java/lang/invoke/CallSite.html)
type. In our example, we use the `name` and `type` to look up the
`HelloInvoke.callme` method, and wrap that inside a
`ConstantCallSite`.

# Invocation of the Bootstrap Method

Let's modify our test case a little:

```
import java.lang.invoke.*;
 
public class HelloInvoke {
    public static void main(String args[]) throws Throwable {
        HelloInvoker.doit();
        HelloInvoker.doit();
    }
 
    static CallSite myBSM(MethodHandles.Lookup lookup,
           String name, MethodType type) throws Throwable {
        Thread.dumpStack();
        MethodType mt = MethodType.methodType(void.class, String.class);
        MethodHandle mh = lookup.findStatic(HelloInvoke.class, name, mt);
        return new ConstantCallSite(mh.asType(type));
    }
 
    static void callme(String x) {
        System.out.println("Hello invokedynamic: " + x);
        Thread.dumpStack();
    }
}

$ java -Djava.lang.invoke.MethodHandle.DUMP_CLASS_FILES=true \
       -XX:+UnlockDiagnosticVMOptions -XX:+ShowHiddenFrames \
       -cp . HelloInvoke
java.lang.Exception: Stack trace
  at HelloInvoke.myBSM(HelloInvoke.java:12)
  at java.lang.invoke.DirectMethodHandle$Holder.invokeStatic()
  at java.lang.invoke.DelegatingMethodHandle$Holder.reinvoke_L()
  at java.lang.invoke.LambdaForm$MH000.invoke_MT000_LLLLL_L()
  at java.lang.invoke.CallSite.makeSite(CallSite.java:311)
  at java.lang.invoke.MethodHandleNatives.linkCallSiteImpl
             (MethodHandleNatives.java:250)
  at java.lang.invoke.MethodHandleNatives.linkCallSite
             (MethodHandleNatives.java:240)
  at HelloInvoker.doit(HelloInvoker.jasm:1000002)
  at HelloInvoke.main(HelloInvoke.java:5)

Hello invokedynamic: yippee!
java.lang.Exception: Stack trace
  at HelloInvoke.callme(HelloInvoke.java:25)
  at java.lang.invoke.DirectMethodHandle$Holder.invokeStatic()
  at java.lang.invoke.LambdaForm$MH001.linkToTargetMethod000_LL_V()
  at HelloInvoker.doit(HelloInvoker.jasm:1000002)
  at HelloInvoke.main(HelloInvoke.java:5)

Hello invokedynamic: yippee!
java.lang.Exception: Stack trace
  at HelloInvoke.callme(HelloInvoke.java:25)
  at java.lang.invoke.DirectMethodHandle$Holder.invokeStatic()
  at java.lang.invoke.LambdaForm$MH001.linkToTargetMethod000_LL_V()
  at HelloInvoker.doit(HelloInvoker.jasm:1000002)
  at HelloInvoke.main(HelloInvoke.java:6)
  ...
```

As expected, the bootstrap method is executed only once, even when the
`invokedynamic` bytecode inside `HelloInvoker.doit()` has been
executed twice.

The call to `HelloInvoke.myBSM` is initiated here in the C code, in
[systemDictionary.cpp](http://hg.openjdk.java.net/jdk/hs/file/ea0d0781c63c/src/hotspot/share/classfile/systemDictionary.cpp#l2833):

```
  JavaCallArguments args;
  args.push_oop(Handle(THREAD, caller->java_mirror()));
  args.push_oop(bsm);
  args.push_oop(method_name);
  args.push_oop(method_type);
  args.push_oop(info);
  args.push_oop(appendix_box);
  JavaValue result(T_OBJECT);
>>JavaCalls::call_static(&result,
                         SystemDictionary::MethodHandleNatives_klass(),
                         vmSymbols::linkCallSite_name(),
                         vmSymbols::linkCallSite_signature(),
                         &args, CHECK_(empty));
  Handle mname(THREAD, (oop) result.get_jobject());

```

and the C callstack looks like this. This happens when the `invokedynamic` bytecode sees that its constant pool entry is not yet resolved.

<pre>
(gdb) where
#0 <a href="http://hg.openjdk.java.net/jdk/hs/file/ea0d0781c63c/src/hotspot/share/classfile/systemDictionary.cpp#l2833">SystemDictionary::find_dynamic_call_site_invoker</a> @ systemDictionary.cpp:2834
#1 <a href="http://hg.openjdk.java.net/jdk/hs/file/ea0d0781c63c/src/hotspot/share/interpreter/linkResolver.cpp#l1776">LinkResolver::resolve_dynamic_call</a>               @ linkResolver.cpp:1782
#2 <a href="http://hg.openjdk.java.net/jdk/hs/file/ea0d0781c63c/src/hotspot/share/interpreter/linkResolver.cpp#l1740">LinkResolver::resolve_invokedynamic</a>              @ linkResolver.cpp:1741
#3 <a href="http://hg.openjdk.java.net/jdk/hs/file/ea0d0781c63c/src/hotspot/share/interpreter/linkResolver.cpp#l1575">LinkResolver::resolve_invoke</a>                     @ linkResolver.cpp:1575
#4 <a href="http://hg.openjdk.java.net/jdk/hs/file/ea0d0781c63c/src/hotspot/share/interpreter/interpreterRuntime.cpp#l868">InterpreterRuntime::resolve_invokedynamic</a>        @ interpreterRuntime.cpp:869
#5 <a href="http://hg.openjdk.java.net/jdk/hs/file/ea0d0781c63c/src/hotspot/share/interpreter/interpreterRuntime.cpp#l897">InterpreterRuntime::resolve_from_cache</a>           @ interpreterRuntime.cpp:897
#6 ?? ()
</pre>

The the C code makes a call to the Java method [`MethodHandleNatives.linkCallSite`](http://hg.openjdk.java.net/jdk/hs/file/ea0d0781c63c/src/java.base/share/classes/java/lang/invoke/MethodHandleNatives.java#l230). This method looks like this

```
class MethodHandleNatives {
    static MemberName linkCallSite(Object callerObj,
                                   Object bootstrapMethodObj,
                                   Object nameObj, Object typeObj,
                                   Object staticArguments,
                                   Object[] appendixResult) {...}
```
`linkCallSite` returns information in two ways:

* It returns an `adapter` object of the `MemberName` type.
* Addition information are returned inside the `appendixResult` array.

*(We will discuss the returned information a bit later.)*

Note that `MethodHandleNatives.linkCallSite` calls [`MethodHandleNatives.linkCallSiteImpl`](http://hg.openjdk.java.net/jdk/hs/file/ea0d0781c63c/src/java.base/share/classes/java/lang/invoke/MethodHandleNatives.java#l245),
which eventually calls
[`CallSite.makeSite`](http://hg.openjdk.java.net/jdk/hs/file/ea0d0781c63c/src/java.base/share/classes/java/lang/invoke/CallSite.java#l311)
that calls `myBSM` using a MethodHandle,


<pre>
static CallSite <a href="http://hg.openjdk.java.net/jdk/hs/file/ea0d0781c63c/src/java.base/share/classes/java/lang/invoke/CallSite.java#l311">makeSite(MethodHandle bootstrapMethod ...)</a> {
    ...
    if (info == null) {
&gt;&gt;     binding = bootstrapMethod.invoke(caller, name, type);
    } else if ...
</pre>

which, as we saw in [my last post on MethodHandle invocation]({% post_url 2017-12-19-lambda-notes-002-method-handle %}), gets magically replaced with the generated method
`LambdaForm$MH000.invoke_MT000_LLLLL_L()`, and eventually through
`DirectMethodHandle$Holder.invokeStatic()`, landing into our bootstrap method
`HelloInvoke.myBSM`.

Now, what happens inside [`MethodHandleNatives.linkCallSiteImpl`](http://hg.openjdk.java.net/jdk/hs/file/ea0d0781c63c/src/java.base/share/classes/java/lang/invoke/MethodHandleNatives.java#l245) is interesting (`myBSM` returns a `ConstantCallSite`):


<pre>
CallSite callSite = CallSite.makeSite(bootstrapMethod,
                                      name,
                                      type,
                                      staticArguments,
                                      caller);
if (callSite instanceof ConstantCallSite) {
    appendixResult[0] = callSite.dynamicInvoker();
    return Invokers.linkToTargetMethod(type);
</pre>

This method returns two pieces of information back to the C code:

  * an `appendix` in `appendixResult[0]`, which contains the information of the resolved `CallSite` returned by `myBSM`.
    * our `CallSite` points to the `HelloInvoke.callme method`.
  * an `adapter` of the type [`MemberName`](http://hg.openjdk.java.net/jdk/hs/file/ea0d0781c63c/src/java.base/share/classes/java/lang/invoke/MemberName.java). In our example, this is returned by <a
href="http://hg.openjdk.java.net/jdk/hs/file/ea0d0781c63c/src/java.base/share/classes/java/lang/invoke/Invokers.java#l520">Invokers.linkToTargetMethod</a>
which generates a LambdaForm (based solely on the `type` of the method we're trying to invoke):

```
static MemberName linkToTargetMethod(MethodType mtype) {
    LambdaForm lform = callSiteForm(mtype, true);
    return lform.vmentry;
}
```

# Resolving CONSTANT_Dynamic in the ConstantPool

To resolve the `CONSTANT_Dynamic` constant pool entry related to an
`invokedynamic` bytecode, we store the `adapter` and `appendix`
into the ConstantPoolCache of this entry.

This resolution process is rather complicated, but the end result is pretty easy to see.
You can set a breakpoint in the following code in [`ConstantPoolCacheEntry::set_method_handle_common`](http://hg.openjdk.java.net/jdk/hs/file/ea0d0781c63c/src/hotspot/share/oops/cpCache.cpp#l360)
and set the variable `TraceInvokeDynamic` to `1`:

```
if (TraceInvokeDynamic) {
  ttyLocker ttyl;
  tty->print_cr("set_method_handle bc=%d appendix=" PTR_FORMAT
                "%s method_type=" PTR_FORMAT "%s method=" PTR_FORMAT " ",
                invoke_code,
                p2i(appendix()),    (has_appendix    ? "" : " (unused)"),
                p2i(method_type()), (has_method_type ? "" : " (unused)"),
                p2i(adapter()));
  adapter->print();
  if (has_appendix)  appendix()->print();
}
```

In our example, the following is printed for `adapter->print()` (simplified):


```
- this oop:          0x00007fff310f65e8
- method holder:     'java/lang/invoke/LambdaForm$MH001'
- name:              'linkToTargetMethod000_LL_V'
- signature:         '(Ljava/lang/Object;Ljava/lang/Object;)V'
 ...
```

To see the code of the adapter method, we can do this inside gdb:

```
(gdb) call ((Method*)0x00007fff310f65e8)->print_codes_on(tty)
0 aload_1
1 checkcast 14 <java/lang/invoke/MethodHandle>
4 aload_0
5 invokehandle 18
    <java/lang/invoke/MethodHandle.invokeBasic(Ljava/lang/Object;)V> 
8 return
```

Alternatively, we can find the generated class from `DUMP_CLASS_FILES/java/lang/invoke/LambdaForm$MH001.class`, and it can be disassembled:


```
static Method linkToTargetMethod000_LL_V:
    "(Ljava/lang/Object;Ljava/lang/Object;)V"
  stack 2 locals 2
{
  aload_1;
  checkcast	class MethodHandle;
  aload_0;
  invokevirtual	Method MethodHandle.invokeBasic:
                      "(Ljava/lang/Object;)V";
  return;
}
```

The following is printed by `appendix()->print()` (simplified):

```
java.lang.invoke.DirectMethodHandle 
- 'customizationCount' 'B' = 0
- 'type' = (Ljava/lang/String;)V
- 'member' 'Ljava/lang/invoke/MemberName;' =
    {method} {0x00007fff310d5770} 'callme' '(Ljava/lang/String;)V'
    in 'HelloInvoke'
...
```

In summary, we store the following in a resolved constant pool entry for `invokedynamic`:

* the `adapter` stores the LambdaForm returned by `Invokers.linkToTargetMethod`
* the `appendix` stores the call site returned by `myBSM`.

# Execution of the InvokeDynamic Bytecode

When an `invokedynamic` bytecode is executed in the interpreter, it does the following:

* Resolve the constant pool entry if necessary (see above)
* Fetch the `adapter` and `appendix`  from the ConstantPoolCacheEntry
* If `appendix` is not null, push it to the stack as a trailing parameter
* Call the `adapter` method

In our example, our adapter `LambdaForm$MH001.linkToTargetMethod000_LL_V` takes in 2 object parameters:

* The first parameter `p1` is the String `"yippee!"`
  * This was pushed by our test program in `HelloInvoker.doit` with the `ldc` bytecode
* The second parameter `p2` is a `DirectMethodHandle` that points to `HelloInvoke.callme`
  * This was pushed by `invokedynamic` as a trailing parameter


It essentially does the following:

```
((MethodHandle)p2)->invokeBasic(p1);
```

As discussed in [my last post on MethodHandle invocation]({% post_url 2017-12-19-lambda-notes-002-method-handle %}), this
will magically result in a call to `HelloInvoke.callme` with the following call stack:

```
Hello invokedynamic: yippee!
java.lang.Exception: Stack trace
  at HelloInvoke.callme(HelloInvoke.java:25)
  at java.lang.invoke.DirectMethodHandle$Holder.invokeStatic()
  at java.lang.invoke.LambdaForm$MH001.linkToTargetMethod000_LL_V()
  at HelloInvoker.doit(HelloInvoker.jasm:1000002)
  at HelloInvoke.main(HelloInvoke.java:5)
```

# Summary

Now we have seen how a very basic `invokedynamic` bytecode is
bootstraped and executed. Next we will see how `invokedynamic` is used
to implement Lambda.
