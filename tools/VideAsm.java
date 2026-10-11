// VideAsm - run Vide's own 6809 assembler (de.malban.vide.assy.Asmj, inside Vide.jar) without the IDE, so the
// command-line build proves the source assembles exactly as Vide assembles it.  It uses the constructor the IDE
// itself calls; the binary lands beside the source as <name>.bin.
//   VIDE_HOME=<Vide dir> java -Djava.awt.headless=true -cp Vide.jar:. VideAsm /abs/path/main.asm [listing.lst]
import java.io.*;
import java.util.HashMap;

public class VideAsm {
    public static void main(String[] args) throws Exception {
        String src = new File(args[0]).getAbsolutePath();
        ByteArrayOutputStream err = new ByteArrayOutputStream();
        OutputStream lst = args.length > 1 ? new FileOutputStream(args[1]) : OutputStream.nullOutputStream();
        new de.malban.vide.assy.Asmj(src, err, lst, OutputStream.nullOutputStream(), OutputStream.nullOutputStream(),
                                     "", new HashMap<>());
        lst.close();
        String e = err.toString().trim();
        if (!e.isEmpty()) { System.err.println(e); }
        System.exit(e.toLowerCase().contains("error") ? 1 : 0);
    }
}
