#ifndef EASYTIER_IOS_BRIDGE_H
#define EASYTIER_IOS_BRIDGE_H
// 返回值由 Rust 分配，Swift 使用后必须释放。输入仅在调用期间借用。
char *et_ios_request(const char *json);
void et_ios_free(char *json);
#endif
