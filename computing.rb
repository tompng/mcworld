require 'pry'
require_relative 'mc_world/world'
require 'chunky_png'
outfile='/Users/tomoya/Library/Application Support/minecraft/saves/computer/region/r.0.0.mca'
class Computer
  VALUE_BITS = 32
  MEM_ADDRESS = {x: 0, y: 0, z: 128}
  SEEK_GET = {x: 0, y:128, z:128}
  SEEK_SET = {x: 1, y:128, z:128}
  MEM_REF = {x: 2, y: 128, z: 128}
  MEM_VALUE = {x:3, y: 128, z: 128}
  OP_DONE = {x:0, y:128, z: 128-1}
  OP_ADD = {x: 16, y: 128, z: 128}
  OP_ADD_CALLBACK = {}
  OP_MULT = {x:32, y:128, z:128}
  OP_MULT_CALLBACK = {}
  DISPLAY = {
    char: {w: 6, h: 10, wn: 20, hn: 12},
    base: {x: 0, y:128, z:0},
    src: {x: 0, y: 132, z: 120},
    next: {x:0, y:132, z: 121},
    callback: {x:1, y:132, z: 121}
  }
  CHARTABLE = {x: 0, y: 0, z: 0}
  def initialize &block
    @world = MCWorld::World.new x: 0, z: 0
    Internal.prepare @world
    instance_eval &block
  end

  def mem_direct_set_command addr, src: MEM_VALUE
    pos = Internal.mem_addr_coord addr
    [
      :clone,
      "#{src[:x]} #{src[:y]} #{src[:z]}",
      "#{src[:x]} #{src[:y]} #{src[:z]+VALUE_BITS}",
      "#{addr[:x]} #{addr[:y]} #{addr[:z]}"
    ].join ' '
  end

  def mem_direct_get_command addr, dst: MEM_VALUE
    pos = Internal.mem_addr_coord addr
    [
      :clone,
      "#{pos[:x]} #{pos[:y]} #{pos[:z]}",
      "#{pos[:x]} #{pos[:y]} #{pos[:z]+VALUE_BITS}",
      "#{dst[:x]} #{dst[:y]} #{dst[:z]}"
    ].join ' '
  end
  def mem_op_begin_command mode
    pos, size = Internal.seek_blocks_info mode
    [
      :clone,
      "#{pos[:x]} #{pos[:y]} #{pos[:z]}",
      "#{pos[:x]} #{pos[:y]} #{pos[:z]+size-1}",
      "#{MEM_ADDRESS[:x]} #{MEM_ADDRESS[:y]} #{MEM_ADDRESS[:z]-size}"
    ].join ' '
  end
  def mem_op_set_callback_command pos
    pos, size = Internal.seek_blocks_info mode
    [
      :clone,
      "#{pos[:x]} #{pos[:y]} #{pos[:z]}",
      "#{pos[:x]} #{pos[:y]} #{pos[:z]}",
      "#{MEM_ADDRESS[:x]} #{MEM_ADDRESS[:y]} #{MEM_ADDRESS[:z]-size+1}"
    ].join ' '
  end
  def mem_op_execute_command
    "setblock #{MEM_ADDRESS[:x]} #{MEM_ADDRESS[:y]} #{MEM_ADDRESS[:z]-1} redstone_block"
  end

  module Internal
    def self.command_data command, redstone: false
      MCWorld::Tag::Hash.new(
        'conditionMet' => MCWorld::Tag::Byte.new(0),
        'auto' => MCWorld::Tag::Byte.new(redstone ? 0 : 1),
        'customName' => MCWorld::Tag::String.new('@'),
        'powered' => MCWorld::Tag::Byte.new(0),
        'Command' => MCWorld::Tag::String.new(command),
        'id' => MCWorld::Tag::String.new('Control'),
        'SuccessCount' => MCWorld::Tag::Int.new(0),
        'TrackOutput' => MCWorld::Tag::Int.new(0),
      )
    end
    def self.clear_value_command
      x, y, z = MEM_VALUE[:x], MEM_VALUE[:y], MEM_VALUE[:z]
      "fill #{x} #{y} #{z} #{x} #{y} #{z+VALUE_BITS} air"
    end
    def self.copy_value_to_ref_command
      x, y, z = MEM_VALUE[:x], MEM_VALUE[:y], MEM_VALUE[:z]
      "clone #{x} #{y} #{z} #{x} #{y} #{z+VALUE_BITS} #{MEM_REF[:x]} #{MEM_REF[:y]} #{MEM_REF[:z]}"
    end
    def self.set_command_blocks world, commands, pos
      x, y, z = 0, 0, 0
      xdir, ydir = 1, 1
      commands = [nil, *commands]
      commands.each_with_index do |op, i|
        command, cond = op
        px, py, pz = x, y, z
        block_x, block_y, block_z = block_pos = [pos[:x]+x, pos[:z]+z, pos[:y]+y]
        flag = false
        (1..16).each{|j|
          break if (x+xdir*j)%16==15
          flag = j and break if commands[i+j].nil? || commands[i+j+1].nil?
          flag = j and break if commands[i+j].size!=2&&commands[i+j+1].size!=2
        }
        if flag
          x += xdir
        elsif (y+ydir) % 16 != 15
          xdir = -xdir
          y += ydir
        else
          ydir = -ydir
          xdir = -xdir
          z += 1
        end
        data = 0
        data |= MCWorld::Block::Data::X_MINUS if px > x
        data |= MCWorld::Block::Data::X_PLUS if px < x
        data |= MCWorld::Block::Data::Y_MINUS if py > y
        data |= MCWorld::Block::Data::Y_PLUS if py < y
        data |= MCWorld::Block::Data::Z_PLUS if pz < z
        # binding.pry
        if command
          block = i==1 ? MCWorld::Block::CommandBlock : MCWorld::Block::ChainCommandBlock;
          data |= MCWorld::Block::Data::MASK if cond
          world[*block_pos] = block[data]
          world.tile_entities[*block_pos] = command_data(command, redstone: i==1)
        end
      end
      {x: pos[:x]+x, y: pos[:z]+z, z: pos[:y]+y}
    end
    def self.op_add_commands addr
      commands = []
      addr1 = addr
      addr2 = addr1.merge x: addr1[:x]+1
      addr3 = addr1.merge x: addr1[:x]+2
      pos=->(base, i=0){
        "#{base[:x]} #{base[:y]} #{base[:z]+i}"
      }
      32.times{|i|
        commands << "testforblocks #{pos[addr2, i]} #{pos[addr2, i]} #{pos[addr3, i]}"
        commands << ["clone #{pos[addr3, i]} #{pos[addr3, i]} #{pos[addr3, i+1]}", true]
        commands << ["fill #{pos[addr2, i]} #{pos[addr3, i]} air", true]
        commands << "clone #{pos[addr3, i]} #{pos[addr3, i]} #{pos[addr2, i]} masked"
        commands << "testforblocks #{pos[addr1, i]} #{pos[addr1, i]} #{pos[addr2, i]}"
        commands << ["clone #{pos[addr2, i]} #{pos[addr2, i]} #{pos[addr3, i]}", true]
        commands << ["fill #{pos[addr1, i]} #{pos[addr2, i]} air", true]
        commands << ["clone #{pos[addr3, i]} #{pos[addr3, i]} #{pos[addr3, i+1]} masked", true]
        commands << "clone #{pos[addr2, i]} #{pos[addr2, i]} #{pos[addr1, i]} masked"
      }
      commands << "fill #{pos[addr2]} #{pos[addr3, VALUE_BITS]} air"
    end

    def self.op_mult_commands addr
      pos=->(base, i=0){"#{base[:x]} #{base[:y]} #{base[:z]+i}"}
      posup=->(base, i=0){"#{base[:x]} #{base[:y]+1} #{base[:z]+i}"}
      addr1 = addr
      addr2 = addr1.merge x: addr1[:x]+1
      add = op_add_commands addr.merge(y: addr[:y]+1)
      commands = []
      32.times{|i|
        commands << "testforblock #{pos[addr1, i]} stone"
        commands << ["clone #{pos[addr2]} #{pos[addr2, VALUE_BITS-1]} #{posup[addr2, i]}", true]
        commands.push *add
      }
      commands << "clone #{posup[addr1]} #{posup[addr2, VALUE_BITS-1]} #{pos[addr1]}"
      commands << "fill #{posup[addr1]} #{posup[addr1, VALUE_BITS-1]} air"
    end

    def self.op_gt_commands addr, eq: false
      pos=->(base, i=0){"#{base[:x]} #{base[:y]} #{base[:z]+i}"}
      addr1 = addr
      addr2 = addr1.merge x: addr1[:x]+1
      out1 = pos[addr1.merge y: addr1[:y]+1]
      out2 = pos[addr1.merge y: addr2[:y]+1]
      commands = []
      if eq
        commands << "testforblocks #{pos[addr1]} #{pos[addr1, VALUE_BITS-1]} #{pos[addr2]}"
        commands << ["fill #{pos[addr1]} #{pos[addr2, VALUE_BITS-1]} air", true]
        commands << "testforblocks #{pos[addr1]} #{pos[addr1, VALUE_BITS-1]} #{pos[addr2]}"
        commands << ["setblock #{pos[addr1]} stone", true]
      end
      commands << "testforblock #{pos[addr1, VALUE_BITS-1]} stone"
      commands << ["testforblock #{pos[addr2, VALUE_BITS-1]} air", true]
      commands << ["setblock #{out1} stone", true]
      commands << "testforblock #{pos[addr1, VALUE_BITS-1]} air"
      commands << ["testforblock #{pos[addr2, VALUE_BITS-1]} stone", true]
      commands << ["setblock #{out2} stone", true]
      (31..0).each do |i|
        2.times{|j|
          commands << "testforblock #{[out2, out1][j]} air"
          commands << ["testforblock #{pos[addr1, i]} #{[:stone, :air][j]}", true]
          commands << ["testforblock #{pos[addr2, i]} #{[:air, :stone][j]}", true]
          commands << ["setblock #{[out1, out2][j]} stone", true]
        }
      end
      commands << "testforblock #{pos[addr1, VALUE_BITS-1]} stone"
      commands << ["clone #{out2} #{out2} #{out1}", true]
      commands << "fill #{pos[addr1]} #{pos[addr2, VALUE_BITS-1]} air"
      commands << "clone #{out1} #{out1} #{pos[addr1]}"
      commands << "fill #{out1} #{out2} air"
      commands
    end

    def self.prepare_display world
      char = DISPLAY[:char]
      char_w, char_h, char_wn, char_hn = char[:w], char[:h], char[:wn], char[:hn]
      src = DISPLAY[:src]
      src_x, src_y, src_z = src[:x], src[:y], src[:z]
      base = DISPLAY[:base]
      base_x, base_y, base_z = base[:x], base[:y], base[:z]
      next_x, next_y, next_z = DISPLAY[:next][:x], DISPLAY[:next][:y], DISPLAY[:next][:z]
      callback = DISPLAY[:callback]
      callback_x, callback_y, callback_z = callback[:x], callback[:y], callback[:z]
      (char_w*char_wn).times{|x|(char_h*char_hn).times{|y|
        world[base_x+x,base_z+1,base_y+y]=MCWorld::Block::BlackWool
      }}
      char_wn.times{|x|
        char_x = base_x + char_w*x
        char_y = base_y
        char_z = base_z
        char_next_x = base_x + char_w*((x+1)%char_wn)
        commands = [
          "setblock #{char_x} #{char_y} #{char_z} air",
          "clone #{src_x} #{src_y} #{src_z} #{src_x+char_w-1} #{src_y+char_h-1} #{src_z} #{char_x} #{char_y} #{char_z+1}",
          "clone #{char_next_x+2} #{char_y+1} #{char_z} #{char_next_x+3} #{char_y+1} #{char_z} #{next_x} #{next_y} #{next_z}",
          "setblock #{OP_DONE[:x]} #{OP_DONE[:y]} #{OP_DONE[:z]} redstone_block"
        ]
        commands << "clone #{base_x} #{base_y} #{base_z+1} #{base_x+char_w*char_wn-1} #{base_y+char_h*(char_hn-1)-1} #{base_z+1} #{base_x} #{base_y+char_h} #{base_z+1} replace force" if x==char_wn-1
        commands << "fill #{base_x} #{char_y} #{char_z+1} #{base_x+char_w*char_wn-1} #{char_y+char_h-1} #{char_z+1} wool 15" if x==char_wn-1

        br_commands = [
          "setblock #{char_x+1} #{char_y} #{char_z} air",
          "clone #{base_x+2} #{base_y+1} #{base_z} #{base_x+3} #{base_y+1} #{base_z} #{next_x} #{next_y} #{next_z}",
          "clone #{base_x} #{base_y} #{base_z+1} #{base_x+char_w*char_wn-1} #{base_y+char_h*(char_hn-1)-1} #{base_z+1} #{base_x} #{base_y+char_h} #{base_z+1} replace force",
          "fill #{base_x} #{base_y} #{char_z+1} #{base_x+char_w*char_wn-1} #{base_y+char_h-1} #{char_z+1} wool 15",
          "setblock #{OP_DONE[:x]} #{OP_DONE[:y]} #{OP_DONE[:z]} redstone_block"
        ]
        commands.each_with_index do |command, i|
          block = i==0 ? MCWorld::Block::CommandBlock : MCWorld::Block::ChainCommandBlock
          world[char_x, char_z, char_y+1+i] = block.y_plus
          world.tile_entities[char_x, char_z, char_y+1+i] = command_data command, redstone: i==0
        end
        br_commands.each_with_index do |command, i|
          block = i==0 ? MCWorld::Block::CommandBlock : MCWorld::Block::ChainCommandBlock
          world[char_x+1, char_z, char_y+1+i] = block.y_plus
          world.tile_entities[char_x+1, char_z, char_y+1+i] = command_data command, redstone: i==0
        end
        2.times{|i|
          command = "setblock #{char_x+i} #{char_y} #{char_z} redstone_block"
          world[char_x+2+i, char_z, char_y+1] = MCWorld::Block::ChainCommandBlock
          world.tile_entities[char_x+2+i, char_z, char_y+1] = command_data command
        }
      }
      2.times{|i|
        world[next_x+i,next_z,next_y] = MCWorld::Block::ChainCommandBlock
        world.tile_entities[next_x+i,next_z,next_y] = command_data(
          "setblock #{base_x+i} #{base_y} #{base_z} redstone_block"
        )
        world[next_x+i,next_z+1,next_y] = MCWorld::Block::CommandBlock.z_minus
        world.tile_entities[next_x+i,next_z+1,next_y] = command_data "setblock ~ ~ ~+1 air", redstone: true
      }
    end

    def self.prepare_chartable world
      base_x,base_y,base_z = CHARTABLE[:x], CHARTABLE[:y], CHARTABLE[:z]
      img = ChunkyPNG::Image.from_file "chars.png"
      cw, ch = DISPLAY[:char][:w], DISPLAY[:char][:h]
      128.times{|i|
        cx = i%16*cw
        cy = i/16*ch
        ch.times{|y|cw.times{|x|
          c = (img[cx+x,cy+y]>>8)/0x10101*3/0xff
          block = [MCWorld::Block::BlackWool,MCWorld::Block::GrayWool,MCWorld::Block::LightGrayWool,MCWorld::Block::WhiteWool][c]
          world[base_x+cx+x,base_z+8,base_y+cy+ch-1-y]=block
        }}
        8.times{|j|
          world[base_x+cx, base_z+j, base_y+cy]=MCWorld::Block::Stone if (i>>j)&1==1
        }
      }
    end


    def self.gen_seek_blocks mode
      raise 'mode get/set' unless [:get, :set].include? mode
      size = 1+7*12+12+2
      blocks = []
      x, y, z = MEM_REF[:x], MEM_REF[:y], MEM_REF[:z]
      memz = MEM_ADDRESS[:z]
      vx, vy, vz = MEM_VALUE[:x], MEM_VALUE[:y], MEM_VALUE[:z]
      add = ->(command, chain: false, cond: false, redstone: false){
        unless command
          blocks << nil
          next
        end
        block = (chain ? MCWorld::Block::ChainCommandBlock : MCWorld::Block::CommandBlock)
        data = MCWorld::Block::Data::Z_MINUS | (cond ? MCWorld::Block::Data::MASK : 0)
        blocks << [block[data], command_data(command, redstone: redstone)]
      }
      add[nil]
      7.times{|i|
        add["testforblock #{x} #{y} #{z+2*i} stone", redstone: true]
        add["clone ~ ~ #{memz-size} ~ ~ #{memz-1} ~#{1<<i} ~ #{memz-size}", chain: true, cond: true]
        add["setblock ~#{1<<i} ~ ~-3 redstone_block", chain: true, cond: true]
        add["fill ~ ~ #{memz-1} ~ ~ #{memz-size} air", chain: true, cond: true]
        add["setblock ~ ~ ~-1 redstone_block", chain: true]
        add[nil]
        add["testforblock #{x} #{y} #{z+2*i+1} stone", redstone: true]
        add["clone ~ ~ #{memz-size} ~ ~ #{memz-1} ~ ~#{1<<i} #{memz-size}", chain: true, cond: true]
        add["setblock ~ ~#{1<<i} ~-3 redstone_block", chain: true, cond: true]
        add["fill ~ ~ #{memz-1} ~ ~ #{memz-size} air", chain: true, cond: true]
        add["setblock ~ ~ ~-1 redstone_block", chain: true]
        add[nil]
      }
      4.times{|i|
        if i==0
          add["testforblock #{x} #{y} #{z+14} #{i%2==1 ? 'stone' : 'air'}", redstone: true]
        else
          add["testforblock #{x} #{y} #{z+14} #{i%2==1 ? 'stone' : 'air'}", chain: true]
        end
        add["testforblock #{x} #{y} #{z+15} #{i/2==1 ? 'stone' : 'air'}", chain: true, cond: true]
        if mode == :get
          add["clone ~ ~ #{memz+VALUE_BITS*i} ~ ~ #{memz+VALUE_BITS*(i+1)} #{vx} #{vy} #{vz}", chain: true, cond: true]
        else
          add["clone #{vx} #{vy} #{vz} #{vx} #{vy} #{vz+VALUE_BITS} ~ ~ #{memz+VALUE_BITS*i}", chain: true, cond: true]
        end
      }
      add["setblock #{OP_DONE[:x]} #{OP_DONE[:y]} #{OP_DONE[:z]} redstone_block", chain: true]
      add["fill ~ ~ #{memz-1} ~ ~ #{memz-size} air", chain: true]
      blocks.reverse
    end
    def self.seek_get_blocks;@seek_get_blocks||=gen_seek_blocks :get;end
    def self.seek_set_blocks;@seek_set_blocks||=gen_seek_blocks :set;end
    def self.seek_blocks_info mode
      if mode == :get
        [SEEK_GET, seek_get_blocks.size]
      elsif mode == :set
        [SEEK_SET, seek_set_blocks.size]
      end
    end
    def self.prepare world
      [[seek_get_blocks, SEEK_GET], [seek_set_blocks, SEEK_SET]].each do |block_tile_entities, pos|
        block_tile_entities.each_with_index{|bt, i|
          block, tile_entity = bt
          world[pos[:x],pos[:z]+i,pos[:y]] = block
          world.tile_entities[pos[:x],pos[:z]+i,pos[:y]] = tile_entity
        }
      end
      OP_ADD_CALLBACK.merge! set_command_blocks(world, op_add_commands(MEM_VALUE.merge(x: MEM_VALUE[:x]+1)), OP_ADD);
      OP_MULT_CALLBACK.merge! set_command_blocks(world, op_mult_commands(MEM_VALUE.merge(x: MEM_VALUE[:x]+1)), OP_MULT);
      prepare_display world
      prepare_chartable world
    end
    def self.mem_addr_coord addr
      x = 0
      y = 0
      z = 0
      7.times{|i|
        x |= (addr>>(1<<(2*i))&1)<<i
        y |= (addr>>(1<<(2*i+1))&1)<<i
      }
      z |= ((addr>>14)&1)<<1
      z |= ((addr>>15)&1)<<2
      {x: MEM_ADDRESS[:x]+x, y: MEM_ADDRESS[:y]+y, z: MEM_ADDRESS[:z]+z}
    end
  end
end

Computer.new do
  pos_get = Computer::SEEK_GET
  pos_set = Computer::SEEK_SET
  @world[pos_get[:x],pos_get[:z]-2,pos_get[:y]-1]=MCWorld::Block::Stone
  @world[pos_set[:x],pos_set[:z]-2,pos_get[:y]-1]=MCWorld::Block::Stone
  @world[pos_get[:x],pos_get[:z]-3,pos_get[:y]] = MCWorld::Block::CommandBlock[MCWorld::Block::Data::Z_MINUS]
  @world.tile_entities[pos_get[:x],pos_get[:z]-3,pos_get[:y]]=Computer::Internal.command_data mem_op_begin_command(:get), redstone: true
  @world[pos_get[:x],pos_get[:z]-4,pos_get[:y]] = MCWorld::Block::ChainCommandBlock[MCWorld::Block::Data::Z_MINUS]
  @world.tile_entities[pos_get[:x],pos_get[:z]-4,pos_get[:y]]=Computer::Internal.command_data mem_op_execute_command
  @world[pos_set[:x],pos_set[:z]-3,pos_set[:y]] = MCWorld::Block::CommandBlock[MCWorld::Block::Data::Z_MINUS]
  @world.tile_entities[pos_set[:x],pos_set[:z]-3,pos_set[:y]]=Computer::Internal.command_data mem_op_begin_command(:set), redstone: true
  @world[pos_set[:x],pos_set[:z]-4,pos_set[:y]] = MCWorld::Block::ChainCommandBlock[MCWorld::Block::Data::Z_MINUS]
  @world.tile_entities[pos_set[:x],pos_set[:z]-4,pos_set[:y]]=Computer::Internal.command_data mem_op_execute_command
  File.write outfile, @world.encode
end

__END__
testforblock bit32 stone
cond clone ~ 64 ~ ~ 128 ~ ~+32 64 ~
cond setblock ~32 ~3 ~ redstone_block
cond fill ~ 64 ~ ~ 128 ~ air
setblock ~ ~+1 ~ restone_block
stone(will be redstone)

8*8
64*

128*128*128

6*7*2
256*256
64*64
data  ptr   code  callback
64bit 14bit 84bit+2bit
val: 16bit 4bit*4

char: 5x8 24x12 120x96


DSL:
variable(:x, :y, :z)
array(y: 100)
var.x = var.y
var.y = var.x[10]
var.x = var.y + var.z
exec_if(var.a + var.b){}.else{}
exec_while(var.y == var.z){}


val_set_reg_#{n} val -> reg             clone clear_redstone next
bin_op_#{type}   result -> val          set_callback set_redstone clear_redstone | next_command
val_set_ref      val -> ref             clone clear_redstone next
const_set_ref    const -> ref           clone clear_redstone next | ref_blocks
const_set_val    const -> val           clone clear_redstone next | val_blocks
mem_get          mem[ref] -> val        get_prepare set_callback set_redstone clear_redstone | next_command
mem_set          val -> mem[ref]        get_prepare set_callback set_redstone clear_redstone | next_command
const_mem_set    val -> mem[const]      clone clear_redstone next | const_blocks
const_mem_get    mem[const] -> val      clone clear_redstone next | const_blocks
jump                                    clear_redstone next
jump_if                                 set_callback1 set_callback2 set_redstone clear_redstone | callback1 next
