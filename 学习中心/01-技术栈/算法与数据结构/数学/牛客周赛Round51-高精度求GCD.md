# 题目

![image-20240715092902438](C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20240715092902438.png)

# 思路分析

a是一个很大的正整数，无法直接求gcd，我们可以通过得到a%b的结果，再带入gcd函数求得结果。

求a%b时，需要通过模拟手算求余数的方法：

按一位取余：

从高位向低位遍历a，将当前位的数字加上上一位取余b的结果*10，进行取余，直到a遍历完成，得到最终的余数即为a%b。

按n位取余：

将字符串a分割成a/n组，每组n位，存进数组arr中，然后对arr进行遍历，重复取余，每次加上上一个元素取余结果*10^n。

https://blog.csdn.net/qq_42956653/article/details/115874842

# 代码

```java

import java.util.Scanner;

public class Main{
    public static void main(String[] args) {
        Scanner sc = new Scanner(System.in);

        String a = sc.next();
        long b =sc.nextLong();

        long ans=0;
        for (int i=0;i<a.length();i++) {
            ans = (ans * 10 +(a.charAt(i) - '0'))%b;
        }
        if (ans == 0) {
            System.out.println(b);
            return;
        } 
        ans = gcd(b,ans);
        System.out.println(ans);
    }

    public static long gcd(long a, long b) {
        if (b == 0) return a;
        return gcd(b, a%b);
    }
}
```

