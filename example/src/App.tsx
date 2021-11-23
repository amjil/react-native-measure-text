import * as React from 'react';

import { StyleSheet, View, Text } from 'react-native';
import { multiply, measure, measureChars } from 'react-native-measure-text';

export default function App() {
  const [result, setResult] = React.useState<Object | undefined>();

  React.useEffect(() => {
    // multiply(3, 7).then(setResult);
    // measure({text: "hello world!", fontSize: 18}).then(setResult);
    measure({text: "hello world! There has been                     problem with your fetch operatioHH", width: 200}).then((data) => {
      console.log(data);
      data.lineInfo.forEach(element => {
        console.log(element);
        function getSum(total, num) {
    return total + num;
}
        console.log(element.charWidths.reduce(getSum))
      });
    })
    .catch(function(error) {
console.log('There has been a problem with your fetch operation: ' + error.message);
 // ADD THIS THROW error
  throw error;
});;
    // measureChars({text: "hello world!", fontSize: 18}).then(setResult);
  }, []);

  return (
    <View style={styles.container}>
      <Text>Result: {result}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  box: {
    width: 60,
    height: 60,
    marginVertical: 20,
  },
});
