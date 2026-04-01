# 1. 下载依赖

```go
go get -u github.com/go-sql-driver/mysql
```

# 2. 使用mysql驱动

```go
func Open(driverName, dataSourceName string) (*DB, error)
```
使用`Open`打开一个`driverName`指定的数据库，`dataSourceName`指定数据源。

```go
import (  
    "database/sql"  
    _ "github.com/go-sql-driver/mysql"  
)  

// 定义一个全局对象db
var db *sql.DB

// 定义一个初始化数据库的函数
func initDB() (err error) {
	// DSN:Data Source Name
	dsn := "user:password@tcp(127.0.0.1:3306)/sql_test?charset=utf8mb4&parseTime=True"
	// 不会校验账号密码是否正确
	// 注意！！！这里不要使用:=，我们是给全局变量赋值，然后在main函数中使用全局变量db
	db, err = sql.Open("mysql", dsn)
	if err != nil {
		return err
	}
	// 尝试与数据库建立连接（校验dsn是否正确）
	err = db.Ping()
	if err != nil {
		return err
	}
	return nil
}
```
**思考**:为什么`defer db.Clost()` 语句不应该写在 `if err != nil`的前面呢？
`defer`关键字是将后面的函数入栈，如果将`defer db.Clost()`放在`panic`前面，那么如果打开数据库失败，依然会执行`db.Close()`，但此时的`db`实际为`nil`。

## 初始化连接

`Open`函数