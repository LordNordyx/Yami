import com.lordnordyx.yami.optimize.RgssArchive;
import java.io.File;
public class T { public static void main(String[] a) throws Exception {
  for (String n : new String[]{"a.rgssad","a.rgss3a"}) {
    RgssArchive r = new RgssArchive(new File(n));
    int w = r.extractAll(new File("out-"+n), true, null);
    System.out.println(n+" v"+r.version+" entries="+r.entries.size()+" written="+w);
  }}}
