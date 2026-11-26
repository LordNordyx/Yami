import struct, os, sys, random
M=0xFFFFFFFF
def xordata(data,key):
    out=bytearray(data)
    for i in range(len(out)):
        out[i]^=(key>>(8*(i%4)))&0xFF
        if i%4==3: key=(key*7+3)&M
    return bytes(out)
def v1(files,path):
    b=bytearray(b"RGSSAD\0\x01"); key=0xDEADCAFE
    for name,data in files:
        nb=name.encode('utf-8')
        b+=struct.pack('<I',len(nb)^key); key=(key*7+3)&M
        for c in nb:
            b.append(c^(key&0xFF)); key=(key*7+3)&M
        b+=struct.pack('<I',len(data)^key); key=(key*7+3)&M
        b+=xordata(data,key)
    open(path,'wb').write(b)
def v3(files,path):
    seed=0x12345678; key=(seed*9+3)&M
    hdr=bytearray(b"RGSSAD\0\x03")+struct.pack('<I',seed)
    table_len=sum(16+len(n.encode()) for n,_ in files)+16
    off=len(hdr)+table_len; table=bytearray(); blobs=bytearray()
    for name,data in files:
        fk=random.getrandbits(32); nb=name.encode()
        table+=struct.pack('<IIII',off^key,len(data)^key,fk^key,len(nb)^key)
        table+=bytes(c^((key>>(8*(i%4)))&0xFF) for i,c in enumerate(nb))
        blobs+=xordata(data,fk); off+=len(data)
    table+=struct.pack('<I',0^key)+b'\0'*12
    open(path,'wb').write(hdr+table+blobs)
random.seed(1)
files=[("Data\\Map001.rxdata",os.urandom(70001)),("Graphics\\Tilesets\\Ünïcode.png",os.urandom(5)),("Data\\Scripts.rxdata",b""),("Audio/BGM/x.ogg",os.urandom(131077))]
os.makedirs('ref',exist_ok=True)
for n,d in files:
    p=os.path.join('ref',n.replace('\\','/')); os.makedirs(os.path.dirname(p),exist_ok=True); open(p,'wb').write(d)
v1(files,'a.rgssad'); v3(files,'a.rgss3a')
