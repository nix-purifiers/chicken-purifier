import java.lang.foreign.*;
import java.lang.invoke.MethodHandle;
import static java.lang.foreign.ValueLayout.JAVA_INT;

public class EmbeddedConsumer {
    public static void main(String[] args) throws Throwable {
        int expected = Integer.parseInt(args[1]);
        SymbolLookup symbols = SymbolLookup.libraryLookup(args[0], Arena.global());
        Linker linker = Linker.nativeLinker();
        MethodHandle initialize = linker.downcallHandle(
            symbols.find("purifier_initialize").orElseThrow(), FunctionDescriptor.of(JAVA_INT));
        MethodHandle answer = linker.downcallHandle(
            symbols.find("purifier_answer").orElseThrow(), FunctionDescriptor.of(JAVA_INT, JAVA_INT));
        System.out.println("initializing native runtime on Java thread");
        if ((int) initialize.invokeExact() != 1) throw new AssertionError("initialize");
        System.out.println("calling native callbacks on initialized Java thread");
        for (int i = 0; i < 100; ++i) {
            if ((int) answer.invokeExact(i) != i + expected) throw new AssertionError("answer");
        }
        System.out.println("Java FFM native egg dependency + embedded callbacks + GC PASS");
    }
}
