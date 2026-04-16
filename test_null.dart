void main() {
  dynamic a = null;
  try {
    double x = a;
    print(x);
  } catch (e) {
    print("Assignment: $e");
  }

  try {
    double x = a as double;
  } catch (e) {
    print("Cast as double: $e");
  }

  try {
    num x = a as num;
  } catch (e) {
    print("Cast as num: $e");
  }

  Map<String, dynamic> data = {'val': null};
  try {
    double x = data['val'];
  } catch (e) {
    print("Dynamic map access: $e");
  }
}
