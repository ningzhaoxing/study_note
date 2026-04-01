# 题目

![image-20240529213030634](C:\Users\Administrator\AppData\Roaming\Typora\typora-user-images\image-20240529213030634.png)

# 思路分析

只需要求选中序列中不为g的倍数的数的个数即可，若个数大于1，则说明该序列无法满足近似GCD,反之该序列满足。也就是判断序列中每个区间中不是g的倍数的个数；由于1，3，6，4不满足，那么1，3，6，4，10也不会满足。

我们可以用前缀和存储区间中不是g倍数的数的个数。如果这个区间的个数大于2，则缩小区间。



# AC代码

```java

import java.util.Scanner;

public class Main {
    public static void main(String[] args) {
        Scanner sc = new Scanner(System.in);
        int n,g;
        n=sc.nextInt();
        g=sc.nextInt();
        int[] a = new int[n+1];
        for (int i = 1; i <= n; i++) {
            int tmp = sc.nextInt();
            if (tmp % g != 0) a[i] = 1;
            a[i]+=a[i-1];
        }
        long ans=0;
        for (int l=1,r=2;r<=n;r++) {
            while(l<r && a[r]-a[l-1] > 1) l++;
            ans += r-l;
        }
        System.out.println(ans);
    }
}

```

