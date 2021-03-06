-- Memory game
-- Copyright 2013 Marc Lepage
-- Licensed under the Apache License, Version 2.0
-- http://www.apache.org/licenses/LICENSE-2.0

GW, GH = 720, 720
GS, GL = math.min(GW, GH), math.max(GW, GH)
ASPECT = GW/GH
BUTTON = 64

game =
{
    players = 1, -- number of players (1 or 2)
    player = 1,  -- current player (1 or 2)
    level = 1,   -- level (1 to 9)
    sizes = {{4,2},{4,3},{4,4},{5,4},{6,4},{6,5},{6,6},{7,6},{8,6}},
    score = {},
}

score = { nil, nil } -- score nodes

local blink = { [0]={ t=0, b=false }, { t=0, b=false }, { t=0, b=false } }

materials = {}

screen = {}
local activeScreen
local activeScreenName, nextScreenName
local transitionNode
local transitionTime

local scene

local digits = {}

local armedButton
local buttonx, buttony
local buttonHandlers = {}

local levelScreenLoaded, gameScreenLoaded = false, false

local sounds = {}

function newQuad(w, h, material, id)
    local node = Node.create(id)

    w, h = w/2, h/2
    node:setModel(Model.create(
        Mesh.createQuad(
            Vector3.new(-w, -h, 0),
            Vector3.new(-w, h, 0),
            Vector3.new(w, -h, 0),
            Vector3.new(w, h, 0))))

    if material then
        node:getModel():setMaterial(material)
    end

    return node
end

function freeDigits()
    for n = 1, #digits do
        for i = 1, #digits[n] do
            digits[n][i]:setTag('used', nil)
        end
    end
end

function newDigit(n)
    if not digits[n] then
        digits[n] = {}
    end
    local digit
    for i = 1, #digits[n] do
        if not digits[n][i]:hasTag('used') then
            digit = digits[n][i]
            break
        end
    end
    if not digit then
        digit = newQuad(BUTTON, BUTTON, 'res/card.material#decal-' .. n)
        digits[n][#digits[n]+1] = digit
    end
    digit:setTag('used', 'true')
    return digit
end

function getDigits(node, n)
    local digit = node:getFirstChild()
    while digit do
        digit:setTag('used', nil)
        node:removeChild(digit)
        digit = node:getFirstChild()
    end
    local s = tostring(n)
    local w = #s * 0.5*BUTTON
    local x = -w/2 + 0.3*BUTTON
    for i = 1, #s do
        digit = newDigit(s:sub(i, i))
        digit:setTranslation(x, 0.025*BUTTON, 0)
        node:addChild(digit)
        x = x + 0.5*BUTTON
    end
    node:setTag('w', tostring(w))
    node:setTag('h', tostring(BUTTON))
end

function newButton(w, h, material, handler)
    local button = newQuad(w, h, material)
    local hkey = tostring(handler)
    button:setTag('button', 'true')
    button:setTag('w', tostring(w))
    button:setTag('h', tostring(h))
    button:setTag('handler', hkey)
    buttonHandlers[hkey] = handler
    return button
end

function setButtonSize(button, w, h)
    button:setTag('w', tostring(w))
    button:setTag('h', tostring(h))
end

function setButtonEnabled(button, enabled)
    if enabled then
        button:setTag('disabled', nil)
    else
        button:setTag('disabled', 'true')
    end
end

function gotoScreen(name, force)
    nextScreenName = name
    transitionTime = 0
    scene:addNode(transitionNode)
end

function loadScreen(name)
    if not screen[name] then
        Game.getInstance():getScriptController():loadScript('res/' .. name .. '.lua')
        if screen[name].load then
            screen[name].load()
        end
    end
end

local function loadSounds()
    sounds[1] = AudioSource.create("res/sfx/click.wav");
    sounds[2] = AudioSource.create("res/sfx/match.wav");
    sounds[3] = AudioSource.create("res/sfx/nomatch.wav");
end

function playSound(index)
    sounds[index]:play()
end

function visitArmButton(node)
    if node:hasTag('button') and not node:hasTag('disabled') then
        local w, h = tonumber(node:getTag('w')), tonumber(node:getTag('h'))
        local x, y = node:getTranslationX(), node:getTranslationY()
        if x-w/2 <= buttonx and buttonx <= x+w/2 and y-h/2 <= buttony and buttony <= y+h/2 then
            local sx, sy = node:getScaleX(), node:getScaleY()
            node:createAnimation('scale', Transform.ANIMATE_SCALE(), 2, { 0, 200 }, { sx,sy,1, 1.2,1.2,1 }, Curve.QUADRATIC_IN_OUT):play()
            armedButton = node
            playSound(1)
        end
        return false
    end
    return true
end

local function armButton(x, y)
    buttonx, buttony = x, y
    scene:visit('visitArmButton')
end

local function disarmButton(x, y)
    buttonx, buttony = x, y
    if armedButton then
        local node = armedButton
        local w, h = tonumber(node:getTag('w')), tonumber(node:getTag('h'))
        local x, y = node:getTranslationX(), node:getTranslationY()
        if not (x-w/2 <= buttonx and buttonx <= x+w/2 and y-h/2 <= buttony and buttony <= y+h/2) then
            local sx, sy = node:getScaleX(), node:getScaleY()
            node:createAnimation('scale', Transform.ANIMATE_SCALE(), 2, { 0, 200 }, { sx,sy,1, 1,1,1 }, Curve.QUADRATIC_IN_OUT):play()
            armedButton = nil
        end
    end
end

local function fireButton(x, y)
    buttonx, buttony = x, y
    if armedButton then
        local node = armedButton
        local sx, sy = node:getScaleX(), node:getScaleY()
        node:createAnimation('scale', Transform.ANIMATE_SCALE(), 2, { 0, 200 }, { sx,sy,1, 1,1,1 }, Curve.QUADRATIC_IN_OUT):play()
        local w, h = tonumber(node:getTag('w')), tonumber(node:getTag('h'))
        local x, y = node:getTranslationX(), node:getTranslationY()
        if x-w/2 <= buttonx and buttonx <= x+w/2 and y-h/2 <= buttony and buttony <= y+h/2 then
            buttonHandlers[node:getTag('handler')](node)
        end
        armedButton = nil
    end
end

local function getLastChild(node)
    local child = node:getFirstChild()
    if child then
        local next = child:getNextSibling()
        while next do
            child, next = next, next:getNextSibling()
        end
    end
    return child
end

local function drawNode(node)
    local model = node:getModel()
    if model then
        model:draw()
    end
    local child = getLastChild(node)
    while child do
        drawNode(child)
        child = child:getPreviousSibling()
    end
end

function keyEvent(event, key)
    if event == Keyboard.KEY_PRESS then
        if key == Keyboard.KEY_ESCAPE then
            Game.getInstance():exit()
        end
    end
end

function touchEvent(event, x, y, id)
    id = id + 1
    if 1 < id then
        return -- ignore extra touches
    end
    if event == Touch.TOUCH_PRESS then
        armButton(x, y)
    elseif event == Touch.TOUCH_RELEASE then
        fireButton(x, y)
    elseif event == Touch.TOUCH_MOVE then
        disarmButton(x, y)
    end
end

function drawSplash()
    local game = Game.getInstance()
    game:clear(Game.CLEAR_COLOR_DEPTH, 1, 1, 1, 1, 1, 0)
    
    local tw1, tw2, tw3, th = 306, 464, 520, 74
    local x1, y1 = GW/2, GH/3
    local x2, y2 = GW/2, GH/3
    local x3, y3 = GW/2, GH*2/3
    if ASPECT <= 1 then
        y1 = y1 - th
        y2 = y2 + th
        y3 = GH*3/4
    else
        local w = tw1 + th + tw2
        x1 = x1 - w/2 + tw1/2
        x2 = x2 + w/2 - tw2/2
    end

    local batch
    batch = SpriteBatch.create("res/title-1.png")
    batch:start()
    batch:draw(x1, y1, 0, tw1, th, 0, 1, 1, 0, Vector4.one(), true)
    batch:finish()
    batch = SpriteBatch.create("res/title-2.png")
    batch:start()
    batch:draw(x2, y2, 0, tw2, th, 0, 1, 1, 0, Vector4.one(), true)
    batch:finish()
    batch = SpriteBatch.create("res/title-3.png")
    batch:start()
    batch:draw(x3, y3, 0, tw3, th, 0, 1, 1, 0, Vector4.one(), true)
    batch:finish()
end

function update(elapsedTime)
    --[[
    if not levelScreenLoaded then
        levelScreenLoaded = screen.level.loadinc()
    elseif not gameScreenLoaded then
        gameScreenLoaded = screen.game.loadinc()
    end
    --]]

    for i = 0, 2 do
        blink[i].t = blink[i].t - elapsedTime/1000
        if blink[i].t <= 0 then
            blink[i].b = not blink[i].b
            if activeScreen and activeScreen.blink then
                activeScreen.blink(i, blink[i].b)
            end
            if blink[i].b then
                blink[i].t = 0.1 + 0.3*math.random()
            else
                blink[i].t = 2 + 8*math.random()
            end
        end
    end

    if transitionTime then
        local updatedTime = transitionTime + elapsedTime/1000
        if transitionTime < 0.2 and 0.2 <= updatedTime then
            if activeScreen then
                scene:removeNode(activeScreen.root)
                if activeScreen.exit then
                    activeScreen.exit()
                end
            end
            loadScreen(nextScreenName)
            activeScreenName, activeScreen = nextScreenName, screen[nextScreenName]
            if activeScreen.enter then
                activeScreen.enter()
            end
            scene:removeNode(transitionNode)
            scene:addNode(activeScreen.root)
            scene:addNode(transitionNode)
        end
        transitionTime = updatedTime
        if updatedTime < 0.4 then
            local a = 1 - math.abs((updatedTime - 0.2) / 0.2)
            local effect = transitionNode:getModel():getMaterial():getTechnique():getPassByIndex(0):getEffect()
            local uniform = effect:getUniform('u_modulateAlpha')
            effect:setValue(uniform, a)
        else
            scene:removeNode(transitionNode)
            transitionTime = nil
        end
    end

    if activeScreen and activeScreen.update then
        activeScreen.update(elapsedTime)
    end
end

function render(elapsedTime)
    Game.getInstance():clear(Game.CLEAR_COLOR_DEPTH, (activeScreen and activeScreen.color) or Vector4.one(), 1, 0)

    -- draw scene in reverse child order since children are added first
    local node = scene:getFirstNode()
    while node do
        drawNode(node)
        node = node:getNextSibling()
    end

    if activeScreen and activeScreen.draw then
        activeScreen.draw()
    end
end

function initialize()
    GW, GH = Game.getInstance():getWidth(), Game.getInstance():getHeight()
    GS, GL = math.min(GW, GH), math.max(GW, GH)
    ASPECT = GW/GH
    BUTTON = GS / 6

    ScreenDisplayer.start("drawSplash", 1000)

    math.randomseed(os.time())

    scene = Scene.create()

    local camera = Camera.createOrthographic(1, 1, 1, 0, 1)

    local matrix = Matrix.new()
    Matrix.createOrthographicOffCenter(0, GW, GH, 0, -100, 100, matrix)
    camera:resetProjectionMatrix()
    camera:setProjectionMatrix(matrix)

    local cameraNode = scene:addNode('camera')
    cameraNode:setCamera(camera)
    scene:setActiveCamera(camera)
    cameraNode:translate(0, 0, 5);

    transitionNode = newQuad(GW, GH, 'res/misc.material#black')
    transitionNode:setTranslation(GW/2, GH/2, 0)
    scene:addNode(transitionNode)

    score[1], score[2] = Node.create(), Node.create()

    for i = 0, 2 do
        blink[i].t = 2 + 8*math.random()
    end

    loadSounds()

    loadScreen('level')
    loadScreen('game')

    gotoScreen('title')
end

function finalize()
end
