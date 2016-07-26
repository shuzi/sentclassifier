#!/opt/share/torch-7.0/bin/th

fbok,_ = pcall(require, 'fbcunn')
if fbok then
   require 'fbcunn'
end
cudnnok,_ = pcall(require, 'cudnn')
if cudnnok then
   require 'cudnn'
   cudnn.fastest = true
   cudnn.benchmark = true
   cudnn.verbose = true
end

cmd = torch.CmdLine('_')
cmd:text()
cmd:text('Options:')
cmd:option('-seed', 1, 'fixed input seed for repeatable experiments')
cmd:option('-threads', 1, 'number of threads')
cmd:option('-optimization', 'SGD', 'optimization method: SGD | ASGD | CG | LBFGS')
cmd:option('-learningRate', 1e-2, 'learning rate at t=0')
cmd:option('-batchSize', 1, 'mini-batch size (1 = pure stochastic)')
cmd:option('-batchSizeTest', 1, 'mini-batch size (1 = pure stochastic)')
cmd:option('-learningRateDecay', 0, 'weight decay (SGD only)')
cmd:option('-momentum', 0, 'momentum (SGD only)')
cmd:option('-t0', 1, 'start averaging at t0 (ASGD only), in nb of epochs')
cmd:option('-maxIter', 2, 'maximum nb of iterations for CG and LBFGS')
cmd:option('-type', 'float', 'type: double | float | cuda')
cmd:option('-trainFile', 'train', 'input training file')
cmd:option('-validFile', 'valid', 'input validation file')
cmd:option('-testFile', 'test', 'input test file')
cmd:option('-embeddingFile', 'embedding', 'input embedding file')
cmd:option('-embeddingDim', 100, 'input word embedding dimension')
cmd:option('-contConvWidth', 2, 'continuous convolution filter width')
cmd:option('-wordHiddenDim', 200, 'first hidden layer output dimension')
cmd:option('-numFilters', 1000, 'CNN filters amount')
cmd:option('-hiddenDim', 1000, 'second hidden layer output dimension')
cmd:option('-numLabels', 311, 'label quantity')
cmd:option('-epoch', 200, 'maximum epoch')
cmd:option('-L1reg', 0, 'L1 regularization coefficient')
cmd:option('-L2reg', 1e-4, 'L2 regularization coefficient')
cmd:option('-trainMaxLength', 150, 'maximum length for training')
cmd:option('-testMaxLength', 150, 'maximum length for valid/test')
cmd:option('-trainMinLength', 40, 'maximum length for training')
cmd:option('-testMinLength', 40, 'maximum length for valid/test')
cmd:option('-gradClip', 0.5, 'gradient clamp')
cmd:option('-gpuID', 1, 'GPU ID')
cmd:option('-outputprefix', 'none', 'output file prefix')
cmd:option('-prevtime', 0, 'time start point')
cmd:option('-usefbcunn', false, 'use fbcunn')
cmd:option('-usecudnn', false, 'use cudnn')
cmd:option('-nesterov', false, 'use nesterov')
cmd:option('-saveMode', 'last', 'last|every')
cmd:option('-valid', false, 'run valid')
cmd:option('-test', false, 'run test')


cmd:text()
opt = cmd:parse(arg or {})
print(opt)
--opt.rundir = cmd:string('experiment', opt, {dir=true})
--paths.mkdir(opt.rundir)
--cmd:log(opt.rundir .. '/log', params)

if opt.usefbcunn == false then
  fbok = false
elseif opt.usefbcunn == true and fbok == true then
  fbok = true
else
  print("Error: fbcunn is not available to use.")
  fbok = false
end


if opt.usecudnn == false then
  cudnnok = false
elseif opt.usecudnn == true and cudnnok == true then
  cudnnok = true
else
  print("Error: cudnn is not available to use.")
  cudnnok = false
end



if opt.type == 'float' then
   print('==> switching to floats')
   require 'torch'
   require 'nn'
   require 'optim'
   torch.setdefaulttensortype('torch.FloatTensor')
elseif opt.type == 'cuda' then
   print('==> switching to CUDA')
   require 'cutorch'
   require 'cunn'
   require 'optim'
   torch.setdefaulttensortype('torch.FloatTensor')
   cutorch.setDevice(opt.gpuID)
   print('GPU DEVICE ID = ' .. cutorch.getDevice())
end
print("####")
print("default tensor type"  .. torch.getdefaulttensortype())
torch.setnumthreads(opt.threads)
torch.manualSeed(opt.seed)
math.randomseed(opt.seed)
mapWordIdx2Vector = torch.Tensor()
mapWordStr2WordIdx = {}
mapWordIdx2WordStr = {}
trainDataSet = {}
validDataSet = {}
testDataSet = {}
trainDataTensor = torch.Tensor()
trainDataTensor_y = torch.Tensor()
validDataTensor = torch.Tensor()
validDataTensor_y = {}
testDataTensor = torch.Tensor()
testDataTensor_y = {}


dofile 'prepareData.lua'
if opt.type == 'cuda' then
  trainDataTensor =  trainDataTensor:cuda()
  trainDataTensor_y =  trainDataTensor_y:cuda()
  validDataTensor = validDataTensor:cuda()
  testDataTensor = testDataTensor:cuda()
end
dofile 'train.lua'
collectgarbage()
collectgarbage()


sys.tic()
epoch = 1
validState = {}
testState = {}
while epoch <= opt.epoch do
   train()
   if opt.valid then
     test(validDataTensor, validDataTensor_y, validState)
   end
   if opt.test then
     test(testDataTensor, testDataTensor_y, testState)
   end
   if opt.outputprefix ~= 'none' then
      if opt.saveMode == 'last' and epoch == opt.epoch then
         local t = sys.toc()
         saveModel(t + opt.prevtime)
         local obj = {
            em = model:get(1).weight,
            s2i = mapWordStr2WordIdx,
            i2s = mapWordIdx2WordStr
         }
         torch.save(opt.outputprefix .. string.format("_%010.2f_embedding", t + opt.prevtime), obj)
      elseif opt.saveMode == 'every'  then
         local t = sys.toc()
         saveModel(t + opt.prevtime)
         local obj = {
            em = model:get(1).weight,
            s2i = mapWordStr2WordIdx,
            i2s = mapWordIdx2WordStr
         }
         torch.save(opt.outputprefix .. string.format("_%010.2f_embedding", t + opt.prevtime), obj)
      end
   end
   epoch = epoch + 1
end

