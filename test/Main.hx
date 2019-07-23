import utest.Runner;
import utest.ui.Report;

class Main {
  public static function main() {
    var runner = new Runner();
    runner.addCases(test);
    Report.create(runner);
    runner.run();
  }
}
