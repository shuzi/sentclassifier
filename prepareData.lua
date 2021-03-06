
require 'torch'
require 'nn'
local stringx = require 'pl.stringx'

init_voc = {}
train_size = 0
valid_size = 0
test_size = 0
train_len = {}
valid_len = {}
test_len = {}

for line in io.lines(opt.trainFile) do
    train_size = train_size + 1
    local text = stringx.split(line, '\t')[2]
    local w = stringx.split(text)
    for i = 1,#w do
        if not init_voc[w[i]] then init_voc[w[i]]=1 end  
    end
    train_len[train_size] = #w
end
for line in io.lines(opt.validFile) do
    valid_size = valid_size + 1
    local text = stringx.split(line, '\t')[2]
    local w = stringx.split(text)
    for i = 1,#w do
        if not init_voc[w[i]] then init_voc[w[i]]=1 end
    end
    valid_len[valid_size] = #w
end
for line in io.lines(opt.testFile) do
    test_size = test_size + 1
    local text = stringx.split(line, '\t')[2]
    local w = stringx.split(text)
    for i = 1,#w do
        if not init_voc[w[i]] then init_voc[w[i]]=1 end
    end
    test_len[test_size] = #w
end
init_size = 0
for k,v in pairs(init_voc) do init_size = init_size + 1 end
init_size = init_size + 2

print(string.format("%s  %f", "Training data length standard deviation: ", torch.std(torch.Tensor(train_len)) )) 
print(string.format("%s  %f", "Training data length mean: ", torch.mean(torch.Tensor(train_len)) ))
local train_cutoff = math.floor(2 * torch.std(torch.Tensor(train_len)) + torch.mean(torch.Tensor(train_len)))
if train_cutoff > opt.trainMaxLength then
   train_cutoff = opt.trainMaxLength
end
if train_cutoff < opt.trainMinLength then
   train_cutoff = opt.trainMinLength
end

print(string.format("%s  %f", "Training data length cutoff: ", train_cutoff))

print(string.format("%s  %f", "Valid data length standard deviation: ", torch.std(torch.Tensor(valid_len)) ))
print(string.format("%s  %f", "Valid data length mean: ", torch.mean(torch.Tensor(valid_len)) ))
local valid_cutoff = math.floor(3 * torch.std(torch.Tensor(valid_len)) + torch.mean(torch.Tensor(valid_len)))
if valid_cutoff > opt.testMaxLength then
   valid_cutoff = opt.testMaxLength
end
if valid_cutoff < opt.testMinLength then
   valid_cutoff = opt.testMinLength
end

print(string.format("%s  %f", "Valid data length cutoff: ", valid_cutoff))

--[[
local cutoff 
if train_cutoff > valid_cutoff then
   cutoff = train_cutoff
else
   cutoff = valid_cutoff
end
opt.cutoff = cutoff
print(string.format("%s  %f", "Final length cutoff: ", cutoff))
--]]
local trainDataTensor_ydim = train_cutoff + opt.contConvWidth + opt.contConvWidth - 1
local validDataTensor_ydim = valid_cutoff + opt.contConvWidth + opt.contConvWidth - 1
local testDataTensor_ydim = valid_cutoff + opt.contConvWidth + opt.contConvWidth - 1
trainDataTensor = torch.Tensor(math.ceil(train_size/opt.batchSize)*opt.batchSize, trainDataTensor_ydim)
trainDataTensor_y = torch.Tensor(math.ceil(train_size/opt.batchSize)*opt.batchSize)
validDataTensor = torch.Tensor(valid_size, validDataTensor_ydim)
testDataTensor = torch.Tensor(test_size, testDataTensor_ydim)

if opt.trainFile ~= 'none' then
    trainFileHandle = assert(io.open(opt.trainFile, 'r'))
end
if opt.validFile ~= 'none' then
    validFileHandle = assert(io.open(opt.validFile, 'r'))
end
if opt.testFile ~= 'none' then
    testFileHandle = assert(io.open(opt.testFile, 'r'))
end
if opt.embeddingFile ~= 'none' then
    embeddingFileHandle = assert(io.open(opt.embeddingFile, 'r'))
end

local BUFSIZE = 2^13
local zeroEmbedding1 = {}
local zeroEmbedding2 = {}
local zeroEmbedding = {}

mapWordIdx2Vector = torch.zeros(init_size, opt.embeddingDim)
function augmentWordIdx2Vector()
  print("augmentWordIdx2Vector!!!!!!!!!!!!!")
  local temp = mapWordIdx2Vector
  mapWordIdx2Vector = torch.zeros(temp:size()[1] + 1000, opt.embeddingDim)
  mapWordIdx2Vector:narrow(1,1,temp:size()[1]):copy(temp)
  temp = nil 
end

mapWordStr2WordIdx['SENTBEGIN'] = 1
mapWordStr2WordIdx['SENTEND'] = 2
mapWordIdx2WordStr[1] = 'SENTBEGIN'
mapWordIdx2WordStr[2] = 'SENTEND'

idx=3
while true do
    local lines, rest = embeddingFileHandle:read(BUFSIZE, '*line')
    if not lines then break end
    if rest then lines = lines .. rest .. '\n'  end
    local b = 0
    local e = 0
    while true do
        b = e + 1
        e = string.find(lines, '\n', b)
        if e == nil then break end
        local line = string.sub(lines, b, e-1)
        local k = string.sub(line, 1, string.find(line, '\t')-1 )
        local v = string.sub(line, string.find(line, '\t')+1, -1 )
        if init_voc[k] then
          local temptable = {}
          for m in string.gmatch(v, "%S+") do
            temptable[#temptable+1] = tonumber(m)
          end
          mapWordIdx2Vector:narrow(1,idx,1):copy(torch.Tensor(temptable))
          mapWordStr2WordIdx[k] = idx
          mapWordIdx2WordStr[idx] = k
          idx = idx + 1
        end
    end
end

ln = 0 
for line in io.lines(opt.trainFile) do
    ln = ln + 1
    for i=1,opt.contConvWidth  do trainDataTensor[ln][i] = mapWordStr2WordIdx['SENTBEGIN']  ; end
    trainDataTensor_y[ln] = tonumber(stringx.split(line, '\t')[1]) 
    local text = stringx.split(line, '\t')[2]
    local w = stringx.split(text)
    local j = opt.contConvWidth + 1
    for i = 1,#w do
       if mapWordStr2WordIdx[w[i]] == nil then
          if idx > mapWordIdx2Vector:size()[1] then
             augmentWordIdx2Vector()
          end
          mapWordStr2WordIdx[w[i]] = idx
          mapWordIdx2WordStr[idx] = w[i]
          local oovEmbedding = {}
          for i=1,opt.embeddingDim do oovEmbedding[i] = math.random(); end
          mapWordIdx2Vector:narrow(1,idx,1):copy(torch.Tensor(oovEmbedding))
          idx = idx + 1
       end
       if j <= trainDataTensor_ydim - opt.contConvWidth + 1 then 
          trainDataTensor[ln][j] = mapWordStr2WordIdx[w[i]]
          j = j + 1
       end
    end
    for r = j,trainDataTensor_ydim do
          trainDataTensor[ln][r] = mapWordStr2WordIdx['SENTEND']
    end
end
while ln < trainDataTensor:size()[1] do
    local i = math.random(1,ln)
    ln = ln + 1
    trainDataTensor_y[ln] = trainDataTensor_y[i]
    trainDataTensor:narrow(1,ln,1):copy( trainDataTensor:narrow(1,i,1) )
end


ln = 0
for line in io.lines(opt.validFile) do
    ln = ln + 1
    local tempL = {}
    for i=1,opt.contConvWidth  do validDataTensor[ln][i] = mapWordStr2WordIdx['SENTBEGIN']  ; end
    for k  in string.gmatch(stringx.split(line, '\t')[1], "%S+") do
       tempL[#tempL+1] = tonumber(k)
    end
    table.insert(validDataTensor_y, tempL)
    local text = stringx.split(line, '\t')[2]
    local w = stringx.split(text)
    local j = opt.contConvWidth + 1
    for i = 1,#w do
       if mapWordStr2WordIdx[w[i]] == nil then
          if idx > mapWordIdx2Vector:size()[1] then
             augmentWordIdx2Vector()
          end
          mapWordStr2WordIdx[w[i]] = idx
          mapWordIdx2WordStr[idx] = w[i]
          local oovEmbedding = {}
          for i=1,opt.embeddingDim do oovEmbedding[i] = math.random(); end
          mapWordIdx2Vector:narrow(1,idx,1):copy(torch.Tensor(oovEmbedding))
          idx = idx + 1
       end
       if j <= validDataTensor_ydim - opt.contConvWidth + 1 then
          validDataTensor[ln][j] = mapWordStr2WordIdx[w[i]]
          j = j + 1
       end
    end
    for r = j,validDataTensor_ydim do
          validDataTensor[ln][r] = mapWordStr2WordIdx['SENTEND']
    end
end


ln = 0
for line in io.lines(opt.testFile) do
    ln = ln + 1
    local tempL = {}
    for i=1,opt.contConvWidth  do testDataTensor[ln][i] = mapWordStr2WordIdx['SENTBEGIN']  ; end
    for k  in string.gmatch(stringx.split(line, '\t')[1], "%S+") do
       tempL[#tempL+1] = tonumber(k)
    end
    table.insert(testDataTensor_y, tempL)
    local text = stringx.split(line, '\t')[2]
    local w = stringx.split(text)
    local j = opt.contConvWidth + 1
    for i = 1,#w do
       if mapWordStr2WordIdx[w[i]] == nil then
          if idx > mapWordIdx2Vector:size()[1] then
             augmentWordIdx2Vector()
          end
          mapWordStr2WordIdx[w[i]] = idx
          mapWordIdx2WordStr[idx] = w[i]
          local oovEmbedding = {}
          for i=1,opt.embeddingDim do oovEmbedding[i] = math.random(); end
          mapWordIdx2Vector:narrow(1,idx,1):copy(torch.Tensor(oovEmbedding))
          idx = idx + 1
       end
       if j <= testDataTensor_ydim - opt.contConvWidth + 1 then
          testDataTensor[ln][j] = mapWordStr2WordIdx[w[i]]
          j = j + 1
       end
    end
    for r = j,testDataTensor_ydim do
         testDataTensor[ln][r] = mapWordStr2WordIdx['SENTEND']
    end
end


print(string.format('training data size: %s x %s', trainDataTensor:size()[1], trainDataTensor:size()[2]))
print(string.format('valid data size: %s x %s', validDataTensor:size()[1], validDataTensor:size()[2]))
print(string.format('test data size: %s x %s', testDataTensor:size()[1], testDataTensor:size()[2]))
print(string.format('mapWordIdx2WordStr size: %s', #mapWordIdx2WordStr))
print(string.format('mapWordIdx2Vector size: %s', mapWordIdx2Vector:size()[1]))

assert(trainFileHandle:close())
assert(validFileHandle:close())
assert(testFileHandle:close())
assert(embeddingFileHandle:close())
collectgarbage()
collectgarbage()
print("At the end of prepareData, amount of memory currently used in Kilobytes:  ", collectgarbage("count"))
