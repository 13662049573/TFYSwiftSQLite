//
//  CTFYSQLCipher.h
//  TFYSwiftSQLiteKit
//
//  Created by 田风有 on 2021/5/9.
//

#ifndef TFY_SQLCIPHER_BRIDGE_H
#define TFY_SQLCIPHER_BRIDGE_H
// A narrow bridge avoids consumer-unsafe Swift compiler flags for SQLITE_HAS_CODEC.
int tfy_sqlcipher_key(void *database, const void *key, int length);
int tfy_sqlcipher_rekey(void *database, const void *key, int length);
#endif
