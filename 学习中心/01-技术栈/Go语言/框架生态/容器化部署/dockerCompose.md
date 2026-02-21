dockerDompose 通过一个单独的 *docker-compose.yml* 模板文件来定义一组相关联的容器，帮助我们实现 *多个相互关联的docker容器的快速部署*。

![[20250222162029.png]]
# 容器编排依赖关系
使用`depend on`以及使用`healthcheck`进行健康检查。