//
//  DSXRLibrary+Opcode.m
//  xref
//
//  Created by Derek Selander on 4/21/19.
//  Copyright © 2019 Selander. All rights reserved.
//

#import "DSXRLibrary+Opcode.h"
#import "miscellaneous.h"
#import "DSXRObjCClass.h"

@import MachO;
@implementation DSXRLibrary (Opcode)

- (void)parseOpcodes {
    assert(self.dyldInfo);
    

    if (!self.addressObjCDictionary) {
        self.addressObjCDictionary = [NSMutableDictionary dictionaryWithCapacity:100];
    }
    
    uint8_t *bind_buffer = &self.data[self.dyldInfo->bind_off + self.file_offset]; 
    int i = 0;
    uint64_t pointer = 0;
    char *symbol = NULL;
    char type = 0;

    
    uint64_t addend = 0;
    uint8_t dylib_ord = 0;
    
    while (i < self.dyldInfo->bind_size) {
        uint8_t opcode = BIND_OPCODE_MASK & bind_buffer[i];
        uint8_t imm = BIND_IMMEDIATE_MASK & bind_buffer[i];
        
        DEBUG_PRINT("0x%04X ", i);
        
        switch (opcode) {
            case BIND_OPCODE_SET_DYLIB_ORDINAL_IMM: { // If less than 4 bytes
                dylib_ord = imm;
                DEBUG_PRINT("BIND_OPCODE_SET_DYLIB_ORDINAL_IMM (%d)\n", imm);
                break;
            } case BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB: { // If greater than 4 bytes
                int datalen = 0;
                uint64_t v = 0;
                r_uleb128_decode(&bind_buffer[++i], &datalen, &v);
                i += datalen - 1;
                DEBUG_PRINT("BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB (0x%llx)\n", v);
                break;
            } case BIND_OPCODE_SET_DYLIB_SPECIAL_IMM: {
                DEBUG_PRINT("BIND_OPCODE_SET_DYLIB_SPECIAL_IMM (%d)\n", imm);
                break;
            } case BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM: {
                symbol = (char *)&bind_buffer[++i];
                while(bind_buffer[i] != BIND_OPCODE_DONE) {
                    i++;
                }
                DEBUG_PRINT("BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM (0x%02x, %s)\n", imm, symbol);
                break;
            } case BIND_OPCODE_SET_TYPE_IMM: {
                type = BIND_IMMEDIATE_MASK & bind_buffer[i];
                DEBUG_PRINT("BIND_OPCODE_SET_TYPE_IMM (%d)\n", type);
                break;
            } case BIND_OPCODE_SET_ADDEND_SLEB: {
                uintptr_t datalen = 0;
                uint64_t v = 0;
                r_sleb128_decode(&bind_buffer[++i], &datalen, &v);
                i += datalen - 1; // -1, cuz i++ later
                addend = v;
                DEBUG_PRINT("BIND_OPCODE_SET_ADDEND_SLEB (0x%llx)\n", v);
                break;
            } case BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB: {
                int datalen = 0;
                uint64_t v = 0;
                r_uleb128_decode(&bind_buffer[++i], &datalen, &v);
                i += datalen - 1; // -1, cuz i++ later

                struct segment_command_64 *seg = (struct segment_command_64 *)self.segmentCommandsArray[imm].longValue;
                pointer = seg->vmaddr + v;
                DEBUG_PRINT("BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB (%d, 0x%08llx) (%p)\n", imm, v, (void*)pointer);
                break;
            } case BIND_OPCODE_ADD_ADDR_ULEB: {
                int datalen = 0;
                uint64_t v = 0;
                r_uleb128_decode(&bind_buffer[++i], &datalen, &v);
                i += datalen - 1; // -1, cuz i++ later
                pointer += v;
                DEBUG_PRINT("BIND_OPCODE_ADD_ADDR_ULEB (0x%llx) (%p)\n", v, (void*)(pointer));
                break;
            } case BIND_OPCODE_DO_BIND: {
                DEBUG_PRINT("BIND_OPCODE_DO_BIND (%p)\n", (void*)pointer);
                [self addToDictionaries:pointer symbol:symbol];
                pointer += PTR_SIZE;
                break;
            } case BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB: {
                int datalen = 0;
                uint64_t v = 0;
                r_uleb128_decode(&bind_buffer[++i], &datalen, &v);
                DEBUG_PRINT("BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB (%08llx) (%p)\n", v, (void*)pointer);
                [self addToDictionaries:pointer symbol:symbol];
                pointer += (v + PTR_SIZE);
                i += datalen - 1;
                break;
            } case BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED: {
                DEBUG_PRINT("BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED (0x%lx) (%p)\n", imm * PTR_SIZE + PTR_SIZE, (void*)pointer);
                [self addToDictionaries:pointer symbol:symbol];
                pointer += imm * PTR_SIZE + PTR_SIZE;
                break;
            } case BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB: {
                int datalen = 0;
                uint64_t v = 0;
                r_uleb128_decode(&bind_buffer[++i], &datalen, &v);
                i += datalen - 1; // -1, cuz i++ later
                uint64 count = v;
                r_uleb128_decode(&bind_buffer[++i], &datalen, &v);
                uint64_t skip = v;
                
                DEBUG_PRINT("BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB (%llu, 0x%08llx)\n", count, v);
                for (int j = 0; j < count; j++) {
                    DEBUG_PRINT("\tDO_BIND (%p)\n", (void*)pointer);
                    [self addToDictionaries:pointer symbol:symbol];
                    pointer += (skip + PTR_SIZE); // do bind, so sizeof(void*)
                }
                i += datalen - 1; // -1, cuz i++ later
                
                break;
            } case BIND_OPCODE_THREADED:
                printf("BIND_OPCODE_THREADED Not implemented!\n");
                assert(0);
                break;
                
            case BIND_SUBOPCODE_THREADED_APPLY:
                printf("BIND_SUBOPCODE_THREADED_APPLY Not implemented!");
                assert(0);
                break;
            case BIND_OPCODE_DONE:
                DEBUG_PRINT("BIND_OPCODE_DONE\n");
                break;
           
            default:
                assert(0);
                break;
        }

        i++;
        pointer += addend;

    }
}

- (void)addToDictionaries:(uintptr_t)address symbol:(char *)symbol {
    
    NSString *s = [NSString stringWithUTF8String:symbol];
    NSNumber *a = @(address);

    if (self.addressObjCDictionary[a]) {
        if (xref_options.debug) {
            dprintf(STDERR_FILENO, "overriding dict: old %s, %p, new; %s, %p\n", self.addressObjCDictionary[a].name.UTF8String, self.addressObjCDictionary[a].address.pointerValue, symbol, (void*)address);
        }
    }
    DSXRObjCClass * obj = [[DSXRObjCClass alloc] initWithAddress:a symbol:s];
    if (!obj) { return; }

    self.addressObjCDictionary[a] = obj;
    self.stringObjCDictionary[s] = obj;
//    dsclass_ref_t ref = ClassRefCreate(address, symbol);
//    hash_add_objcref_str(ref);
//    hash_add_objcref_addr(ref);
}

@end



