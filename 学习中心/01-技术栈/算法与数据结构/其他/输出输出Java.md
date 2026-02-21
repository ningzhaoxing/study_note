# 快速流

```c++

public class Main {
    public static void main(String[] args) throws IOException {
       Read sc = new Read(System.in);
       BufferedWriter bw = new BufferedWriter(new OutputStreamWriter(System.out));
       int n = sc.nextInt();
       bw.write("Yes");
       
       bw.flush();
       bw.close();
    }
}


class Read {
    public BufferedReader reader;
    public StringTokenizer tokenizer;
    
    public Read(InputStream stream) {
       reader = new BufferedReader(new InputStreamReader(stream), 32768);
       tokenizer = null;
    }
    
    public String next() {
       while (tokenizer == null || !tokenizer.hasMoreTokens()) {
          try {
             tokenizer = new StringTokenizer(reader.readLine());
          } catch (IOException e) {
             throw new RuntimeException(e);
          }
       }
       return tokenizer.nextToken();
    }
    
    public String nextLine() {
       String str = null;
       try {
          str = reader.readLine();
       } catch (IOException e) {
          // TODO 自动生成的 catch 块
          e.printStackTrace();
       }
       return str;
    }
    
    public int nextInt() {
       return Integer.parseInt(next());
    }
    
    public long nextLong() {
       return Long.parseLong(next());
    }
    
    public Double nextDouble() {
       return Double.parseDouble(next());
    }
    
    public BigInteger nextBigInteger() {
       return new BigInteger(next());
    }
}
```

