# dockerfile指令
关键字：
```dockerfile
FROM         # 基础镜像，当前新镜像是基于哪个镜像的
MAINTAINER   # 镜像维护者的姓名混合邮箱地址
RUN          # 容器构建时需要运行的命令
EXPOSE       # 当前容器对外保留出的端口
WORKDIR      # 指定在创建容器后，终端默认登录的进来工作目录，一个落脚点
ENV          # 用来在构建镜像过程中设置环境变量
ADD          # 将宿主机目录下的文件拷贝进镜像且ADD命令会自动处理URL和解压tar压缩包
COPY         # 类似ADD，拷贝文件和目录到镜像中！
VOLUME       # 容器数据卷，用于数据保存和持久化工作
CMD          # 指定一个容器启动时要运行的命令，dockerFile中可以有多个CMD指令，但只有最后一个生效！
ENTRYPOINT   # 指定一个容器启动时要运行的命令！和CMD一样
ONBUILD      # 当构建一个被继承的DockerFile时运行命令，父镜像在被子镜像继承后，父镜像的ONBUILD被触发
```

## ADD和COPY的区别
ADD会在文件拷贝进镜像的基础上，自动处理
