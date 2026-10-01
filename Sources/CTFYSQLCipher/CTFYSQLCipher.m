//
//  CTFYSQLCipher.m
//  TFYSwiftSQLiteKit
//
//  Created by 田风有 on 2021/5/9.
//

#include "CTFYSQLCipher.h"
#include <SQLCipher/sqlite3.h>

int tfy_sqlcipher_key(void *database, const void *key, int length) {
    return sqlite3_key((sqlite3 *)database, key, length);
}

int tfy_sqlcipher_rekey(void *database, const void *key, int length) {
    return sqlite3_rekey((sqlite3 *)database, key, length);
}
