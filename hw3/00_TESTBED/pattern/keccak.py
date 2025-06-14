# Keccak Hash Function Implementation in Python

# l = 4
# w = 2 ^ l = 16
# b = 25 * w = 400
# c = 2 * 64 = 128
# r = b - c  = 272

# Rotation offsets for Rho step
ROTATION_OFFSETS = [[ 0,  4,  3,  9,  2],
                    [ 1, 12, 10, 13,  2],
                    [14,  6, 11, 15, 13],
                    [12,  7,  9,  5,  8],
                    [11,  4,  7,  8, 14]]

# Round constants for Iota step
ROUND_CONSTANTS = [
    0x0001, 0x8082, 0x808A, 0x8000, 0x808B, 0x0001,
    0x8081, 0x8009, 0x008A, 0x0088, 0x8009, 0x000A,
    0x808B, 0x008B, 0x8089, 0x8003, 0x8002, 0x0080,
    0x800A, 0x000A, 0x8081, 0x8080, 0x0001, 0x8008
]

def rot(val, r_bits):
    """Rotate left function"""
    return ((val << r_bits) | (val >> (16 - r_bits))) & 0xFFFF

def pad_message(message, block_size):
    """Pads the input message to fit Keccak block size
    Padding format: message || 0x01 || 0x00...00 || 0x80
    """
    # 0x01 for keccak
    # 0x06 for sha3
    padding = b'\x01' + b'\x00' * ((block_size - len(message) % block_size - 2) % block_size) + b'\x80'
    return message + padding

def theta(state):
    """Theta step for diffusion across the state array"""
    column_xor = [0] * 5
    for x in range(5):
        for y in range(5):
            column_xor[x] ^= state[x][y]
            
    for x in range(5):
        d = column_xor[(x - 1) % 5] ^ rot(column_xor[(x + 1) % 5], 1)
        
        #print((column_xor[(x - 1) % 5].to_bytes(2, byteorder='little')[::-1]).hex())  
        #print((rot(column_xor[(x + 1) % 5], 1).to_bytes(2, byteorder='little')[::-1]).hex())  
        #print((d.to_bytes(2, byteorder='little')[::-1]).hex())
        
        for y in range(5):
            state[x][y] ^= d
            
    return state

def rho(state):
    """Rho step for bitwise rotation"""
    for x in range(5):
        for y in range(5):
            state[x][y] = rot(state[x][y], ROTATION_OFFSETS[x][y])
            
    
    # for y in range(5):
    #     for x in range(5):
    #         print((state[x][y].to_bytes(2, byteorder='little')[::-1]).hex())       
    
            
            
    return state

def pi(state):
    """Pi step for permuting matrix indices"""
    new_state = [[0] * 5 for _ in range(5)]
    for x in range(5):
        for y in range(5):
            new_state[y][(2 * x + 3 * y) % 5] = state[x][y]
    return new_state

def chi(state):
    """Chi step for non-linear transformation"""
    new_state = [[0] * 5 for _ in range(5)]
    for x in range(5):
        for y in range(5):
            new_state[x][y] = state[x][y] ^ ((~state[(x + 1) % 5][y]) & state[(x + 2) % 5][y])
    return new_state

def iota(state, round_index):
    """Iota step for adding round constants"""
    state[0][0] ^= ROUND_CONSTANTS[round_index]
    
    # for y in range(5):
    #     for x in range(5):
    #         print((state[x][y].to_bytes(2, byteorder='little')[::-1]).hex()) 
    
    return state

def keccak_permutation(state):
    """Applies full Keccak permutation rounds"""
    # 12 + 2l = 20
    for round_index in range(20):
        state = theta(state)
        state = rho(state)
        state = pi(state)
        state = chi(state)
        state = iota(state, round_index)
    return state

def keccak_64(input_message, bit_length=64):
    """Main function to compute Keccak hash"""
    block_size = 50 - (2 * (bit_length // 8))
    padded_message = pad_message(input_message.encode(), block_size)
    
    input_pattern = []
    for i in range(0, len(padded_message), 16):
        input_pattern.append(int.from_bytes(padded_message[i:i + 16], byteorder='little'))
        # print(f"Input data {len(input_pattern)-1:2}: {input_pattern[-1]:0{16 * 2}x}")
        
        
        
      
    # hex_data = '8000000000000000000000000000000000000000000174636E75662068736168206B'

    # # 將十六進位字串轉換為 bytes
    # data_bytes = bytes.fromhex(hex_data)

    # # 反轉字節順序 (little-endian)
    # little_endian_data = data_bytes[::-1]
    # padded_message = little_endian_data
        
        
        
        
    
    ########## Chip Start ##########

    # Initialize state array
    state = [[0] * 5 for _ in range(5)]

    # Absorb phase: Process input in chunks
    for i in range(0, len(padded_message), block_size):
        block = padded_message[i:i + block_size]
        for j in range(0, block_size, 2):
            x, y = (j // 2) % 5, (j // 2) // 5
            state[x][y] ^= int.from_bytes(block[j:j + 2], byteorder='little')
        state = keccak_permutation(state)
    
    
    
    
    
    

    # print((state[3][0].to_bytes(2, byteorder='little')[::-1]).hex())
    # print((state[2][0].to_bytes(2, byteorder='little')[::-1]).hex())
    # print((state[1][0].to_bytes(2, byteorder='little')[::-1]).hex())
    # print((state[0][0].to_bytes(2, byteorder='little')[::-1]).hex())




    #Squeeze phase: Extract output hash
    hash_output = b''
    while len(hash_output) < bit_length // 8:
        for i in range(0, block_size, 2):
            x, y = (i // 2) % 5, (i // 2) // 5
            if len(hash_output) < bit_length // 8:
                hash_output += state[x][y].to_bytes(2, byteorder='little')
        state = keccak_permutation(state)
    

    ####### Chip End ##########
    return hash_output[:bit_length // 8].hex()

# Example usage
message = "Hello, Keccak!"
hash_result = keccak_64(message)
print(f"Keccak-64 Hash: {hash_result}")



