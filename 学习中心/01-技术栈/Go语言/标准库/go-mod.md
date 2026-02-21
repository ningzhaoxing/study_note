# Go Mod

## 设置go.mod基础命令

- 初始化`go mod`文件

  `go mod init [模块名]`

- 下载依赖的`module`到本地`cache`

  `go mod download`

- 增加丢失的`module`，删去多余的`module`

  `go mod tidy`

- 将依赖复制到`vendor`下

  `go mod vendor`

## go.mod提供的四大命令

- `module`指定包的名字(路径)

- `require`指定项目第三方依赖

- `replace`替换require中声明的依赖，使用另外的依赖及其版本号

  **使用场景：**

  1. 将依赖替换为别的版本

     ```go
     replace github.com/google/uuid v1.1.1 => github.com/google/uuid v1.1.0		
     # 但实际使用的是  1.1.0 版本，因为可能觉得 1.1.1 版本不好用，因此偷梁换柱
     ```

  2. 引入本地包，进行依赖调试和测试

     ```go
     replace github.com/google/uuid v1.1.1 => ../uuid				
     # 本地路径，可以使用绝对路径或相对路径
     ```

  3. replace 替换不可下载的包，换为其他镜像源

     ```go
     replace golang.org/x/text v0.3.2 => github.com/golang/text v0.3.2 # 替换为其他可用的包，镜像源（功能都一致）
     ```

  4. 使用 fork 仓库

     ```go
     # 假设目前 uuid 开源包 v1.1.1 发现重大bug，此时我们将其 fork 进行 bug 修复，之后替换为我们修复后的版本
     # 注意 开源仓库修复后，最好还是改为开源仓库地址
     replace 
     github.com/google/uuid v1.1.1 =>github.com/RainbowMango/uuid v1.1.2
     ```

  5. 禁止被依赖情况

     ```go
     # k8s 不希望【自己整体】被外部引用，希望外部引用时采用组件方式
     # 因此，k8s 的 mod 标记所有版本 v0.0.0
     # 但 k8s 内部也不认识呀，怎么办？ —— 采用 replace，替换为可用的
     # 但是外部 k8s 整体包的时候，不也是具有 replace 吗？ —— 有是有，但是他们不认识
     # 【外部引用只会引用 require部分，忽略replace部分】，这样外部就只能看到 v0.0.0 版本，但就是找不到相关的包
     # `replace`指令在当前模块不是`main module`时会被自动忽略的，Kubernetes正是利用了这一特性来实现对外隐藏依赖版本号来实现禁止直接引用的目的。
     module k8s.io/kubernetes
     ```

- `exclude`排除项目第三方模块

  **使用场景：**

  1. 第三方模块有bug(或者只满足某类项目使用，某类项目不能使用)