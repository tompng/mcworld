require 'bundler/inline'

gemfile do
  source 'https://rubygems.org/'

  gem 'pry'
  gem 'chunky_png'
end

require_relative 'mc_world/world'
require_relative 'dsl'
outfile=File.expand_path('~/Library/Application Support/minecraft/saves/computer/region/r.0.0.mca')

class Computer
  VALUE_BITS = 32
  MEM_ADDRESS = {x: 0, y: 0, z: 128}
  SEEK_GET = {x: 0, y:128, z:128}
  SEEK_SET = {x: 1, y:128, z:128}
  MEM_REF = {x: 2, y: 128, z: 128}
  MEM_VALUE = {x:3, y: 128, z: 128}
  REG_VALUE = {x: 4, y: 128 ,z: 128}
  REG_TMP_VALUE = {x: 5, y: 128 ,z: 128}
  OP_DONE = {x:0, y:128+4, z: 128}
  CALLBACK = {x:OP_DONE[:x], y: OP_DONE[:y], z: OP_DONE[:z]+2}
  OP_MULT = {x:32, y:128, z:128}
  op_x, op_y, op_z = 16, 128, 128
  OP_MEM_READ = {x: op_x, y: op_y, z: op_z};op_z+=4
  OP_MEM_WRITE = {x: op_x, y: op_y, z: op_z};op_z+=4
  OP_ADD = {x: op_x, y: op_y, z: op_z};op_z+=4
  OP_GT = {x: op_x, y: op_y, z: op_z};op_z+=4
  OP_GTEQ = {x: op_x, y: op_y, z: op_z};op_z+=4
  OP_LT = {x: op_x, y: op_y, z: op_z};op_z+=4
  OP_LTEQ = {x: op_x, y: op_y, z: op_z};op_z+=4
  OP_PUTC = {x: op_x, y: op_y, z: op_z};op_z+=4
  CODE = {x: 0, y: 128+32, z: 128}
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
  def add_compiled_code code
    Internal.add_compiled_code @world, code
  end

  module Internal
    module PointUtil
      def mc_pos pos, dif={}
        "#{pos[:x]+(dif[:x]||0)} #{pos[:y]+(dif[:y]||0)} #{pos[:z]+(dif[:z]||0)}"
      end
      def mc_bit_range pos, dif={}
        mc_bits_range 1, pos, dif
      end
      def mc_byte_range pos, dif={}
        mc_bits_range 8, pos, dif
      end
      def mc_short_range pos, dif={}
        mc_bits_range 16, pos, dif
      end
      def mc_int_range pos, dif={}
        mc_bits_range 32, pos, dif
      end
      def mc_bits_range bits, pos, dif
        [
          "#{pos[:x]+(dif[:x]||0)} #{pos[:y]+(dif[:y]||0)} #{pos[:z]+(dif[:z]||0)}",
          "#{pos[:x]+(dif[:x]||0)} #{pos[:y]+(dif[:y]||0)} #{pos[:z]+(dif[:z]||0)+bits-1}"
        ].join ' '
      end
    end
    extend PointUtil
    module BaseOp
      extend PointUtil
      def self.reg_set idx
        normal_commands idx, "clone #{mc_int_range MEM_VALUE} #{mc_pos REG_VALUE}"
      end
      def self.read idx, address
        normal_commands idx, "clone #{mc_int_range Internal.mem_addr_coord(address)} #{mc_pos MEM_VALUE}"
      end
      def self.write idx, address
        normal_commands idx, "clone #{mc_int_range MEM_VALUE} #{mc_pos Internal.mem_addr_coord(address)}"
      end
      def self.! idx
        normal_commands(idx,
          "fill #{mc_int_range MEM_VALUE} air",
          ["setblock #{mc_pos MEM_VALUE} stone"]
        )
      end
      def self.== idx
        normal_commands(idx,
          "testforblocks #{mc_int_range MEM_VALUE} #{mc_pos REG_VALUE}",
          ["setblock #{mc_pos REG_TMP_VALUE} stone"],
          "clone #{mc_bit_range REG_TMP_VALUE} #{mc_pos MEM_VALUE}",
          "fill #{mc_pos REG_VALUE} #{mc_pos REG_TMP_VALUE, z: 32} air"
        )
      end
      def self.!= idx
        normal_commands(idx,
          "setblock #{mc_pos REG_TMP_VALUE} stone",
          "testforblocks #{mc_int_range MEM_VALUE} #{mc_pos REG_VALUE}",
          ["setblock #{mc_pos REG_TMP_VALUE} air"],
          "clone #{mc_bit_range REG_TMP_VALUE} #{mc_pos MEM_VALUE}",
          "fill #{mc_pos REG_VALUE} #{mc_pos REG_TMP_VALUE, z: 32} air"
        )
      end
      def self.val_set idx, val
        normal_commands idx, *32.times.map{|i|
          "setblock #{mc_pos MEM_VALUE, z: i} #{[:air, :stone][(val>>i)&1]}"
        }
      end
      def self.jump idx, dst_idx
        [begin_command(idx), end_command(dst_idx)]
      end
      def self.jump_if idx, true_idx, false_idx
        [
          begin_command(idx),
          "fill #{mc_int_range MEM_VALUE} air",
          ["setblock #{mc_pos MEM_VALUE} stone"],
          "testforblock #{mc_pos MEM_VALUE} stone",
          [end_command(true_idx || idx+1)],
          "testforblock #{mc_pos MEM_VALUE} air",
          [end_command(false_idx || idx+1)]
        ]
      end
      {
        putc: OP_PUTC, mem_read: OP_MEM_READ, mem_write: OP_MEM_WRITE, :+ => OP_ADD,
        :* => OP_MULT, :> => OP_GT, :>= => OP_GTEQ, :< => OP_LT, :<= => OP_LTEQ
      }.each do |op, pos|
        define_singleton_method op do |idx|
          callback_commands idx, "setblock #{mc_pos pos} redstone_block"
        end
      end
      def self.ref_set idx
        normal_commands idx, "clone #{mc_short_rage MEM_VALUE} #{mc_pos MEM_REF}"
      end
      def self.begin_command idx
        "setblock #{mc_pos code_pos idx} air"
      end
      def self.end_command dst
        "setblock #{mc_pos code_pos dst} redstone_block"
      end
      def self.callback_commands idx, *commands
        offset = 2+commands.size
        [
          begin_command(idx),
          "clone ~ ~ ~#{offset} ~ ~ ~#{offset} #{mc_pos CALLBACK}",
          *commands,
          nil,
          end_command(idx+1)
        ]
      end
      def self.normal_commands idx, *commands
        [begin_command(idx), *commands, end_command(idx+1)]
      end
      def self.code_pos idx, z=0
        {
          x: CODE[:x]+idx%128,
          y: CODE[:y]+idx/128,
          z: CODE[:z]+z
        }
      end
    end
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
      commands = [nil, "setblock ~-1 ~ ~ air", *commands]
      commands.each_with_index do |op, i|
        command, _ = op
        cond = Array === op
        px, py, pz = x, y, z
        block_x, block_y, block_z = block_pos = [pos[:x]+x, pos[:z]+z, pos[:y]+y]
        flag = false
        (1..16).each{|j|
          break if (x+xdir*j)%16==15
          flag = j and break if commands[i+j].nil? || commands[i+j+1].nil?
          flag = j and break if !(Array===commands[i+j])&&!(Array===commands[i+j+1])
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
        if command
          block = i==1 ? MCWorld::Block::CommandBlock : MCWorld::Block::ChainCommandBlock;
          data |= MCWorld::Block::Data::MASK if cond
          world[*block_pos] = block[data]
          world.tile_entities[*block_pos] = command_data(command, redstone: i==1)
        end
      end
      {x: pos[:x]+x, y: pos[:z]+z, z: pos[:y]+y}
    end

    def self.op_mem_commands mode
      pos, size = seek_blocks_info mode
      [
        "clone #{mc_pos pos} #{mc_pos pos, z: size-1} #{mc_pos MEM_ADDRESS, z: -size}",
        "setblock #{mc_pos MEM_ADDRESS, z: -1} redstone_block"
      ]
    end
    def mem_op_execute_command
      "setblock #{MEM_ADDRESS[:x]} #{MEM_ADDRESS[:y]} #{MEM_ADDRESS[:z]-1} redstone_block"
    end

    def self.add_compiled_code world, code
      code.each_with_index do |code, idx|
        commands = BaseOp.send code.first, idx, *code.drop(1)
        commands.each.with_index(1){|command, j|
          next unless command
          pos = BaseOp.code_pos(idx, j)
          block = j==1 ? MCWorld::Block::CommandBlock : MCWorld::Block::ChainCommandBlock
          data = MCWorld::Block::Data::Z_PLUS
          data |= MCWorld::Block::Data::MASK if Array === command
          world[pos[:x], pos[:z], pos[:y]] = block[data]
          world.tile_entities[pos[:x], pos[:z], pos[:y]] = command_data *command, redstone: j==1
        }
      end
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
        commands << ["clone #{pos[addr3, i]} #{pos[addr3, i]} #{pos[addr3, i+1]}"]
        commands << ["fill #{pos[addr2, i]} #{pos[addr3, i]} air"]
        commands << "clone #{pos[addr3, i]} #{pos[addr3, i]} #{pos[addr2, i]} masked"
        commands << "testforblocks #{pos[addr1, i]} #{pos[addr1, i]} #{pos[addr2, i]}"
        commands << ["clone #{pos[addr2, i]} #{pos[addr2, i]} #{pos[addr3, i]}"]
        commands << ["fill #{pos[addr1, i]} #{pos[addr2, i]} air"]
        commands << ["clone #{pos[addr3, i]} #{pos[addr3, i]} #{pos[addr3, i+1]} masked"]
        commands << "clone #{pos[addr2, i]} #{pos[addr2, i]} #{pos[addr1, i]} masked"
      }
      commands << "fill #{pos[addr2]} #{pos[addr3, VALUE_BITS]} air"
      commands << "setblock #{mc_pos OP_DONE} redstone_block"
      commands
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
        commands << ["clone #{pos[addr2]} #{pos[addr2, VALUE_BITS-1]} #{posup[addr2, i]}"]
        commands.push *add
      }
      commands << "clone #{posup[addr1]} #{posup[addr2, VALUE_BITS-1]} #{pos[addr1]}"
      commands << "fill #{posup[addr1]} #{posup[addr1, VALUE_BITS-1]} air"
      commands << "setblock #{mc_pos OP_DONE} redstone_block"
      commands
    end

    def self.op_gt_commands addr, swap: false, eq: false
      pos=->(base, i=0){"#{base[:x]} #{base[:y]} #{base[:z]+i}"}
      addr1 = addr
      addr2 = addr1.merge x: addr1[:x]+1
      out1 = pos[addr1.merge y: addr1[:y]+1]
      out2 = pos[addr1.merge y: addr2[:y]+1]
      commands = []
      if swap
        commands << "clone #{mc_int_range REG_VALUE} #{mc_pos REG_TMP_VALUE}"
        commands << "clone #{mc_int_range MEM_VALUE} #{mc_pos REG_VALUE}"
        commands << "clone #{mc_int_range REG_TMP_VALUE} #{mc_pos MEM_VALUE}"
        commands << "fill #{mc_int_range REG_TMP_VALUE} air"
      end
      if eq
        commands << "testforblocks #{pos[addr1]} #{pos[addr1, VALUE_BITS-1]} #{pos[addr2]}"
        commands << ["fill #{pos[addr1]} #{pos[addr2, VALUE_BITS-1]} air"]
        commands << "testforblocks #{pos[addr1]} #{pos[addr1, VALUE_BITS-1]} #{pos[addr2]}"
        commands << ["setblock #{pos[addr1]} stone"]
      end
      commands << "testforblock #{pos[addr1, VALUE_BITS-1]} stone"
      commands << ["testforblock #{pos[addr2, VALUE_BITS-1]} air"]
      commands << ["setblock #{out1} stone"]
      commands << "testforblock #{pos[addr1, VALUE_BITS-1]} air"
      commands << ["testforblock #{pos[addr2, VALUE_BITS-1]} stone"]
      commands << ["setblock #{out2} stone"]
      (31..0).each do |i|
        2.times{|j|
          commands << "testforblock #{[out2, out1][j]} air"
          commands << ["testforblock #{pos[addr1, i]} #{[:stone, :air][j]}"]
          commands << ["testforblock #{pos[addr2, i]} #{[:air, :stone][j]}"]
          commands << ["setblock #{[out1, out2][j]} stone"]
        }
      end
      commands << "testforblock #{pos[addr1, VALUE_BITS-1]} stone"
      commands << ["clone #{out2} #{out2} #{out1}"]
      commands << "fill #{pos[addr1]} #{pos[addr2, VALUE_BITS-1]} air"
      commands << "clone #{out1} #{out1} #{pos[addr1]}"
      commands << "fill #{out1} #{out2} air"
      commands << "setblock #{mc_pos OP_DONE} redstone_block"
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
      commands = [
        "fill #{DISPLAY[:src][:x]} #{DISPLAY[:src][:y]} #{DISPLAY[:src][:z]} #{DISPLAY[:src][:x]+cw-1} #{DISPLAY[:src][:y]+ch-1} #{DISPLAY[:src][:z]} wool 15"
      ]
      (32..127).each do |i|
        bx, by, bz = base_x+i%16*cw, base_y+i/16*ch, base_z
        commands << "testforblocks #{bx} #{by} #{bz} #{bx} #{by} #{bz+7} #{MEM_VALUE[:x]} #{MEM_VALUE[:y]} #{MEM_VALUE[:z]}"
        commands << ["clone #{bx} #{by} #{bz+8} #{bx+cw-1} #{by+ch-1} #{bz+8} #{DISPLAY[:src][:x]} #{DISPLAY[:src][:y]} #{DISPLAY[:src][:z]}"]
        commands << "" if i%3 == 0
        commands << "" if i%3 == 0
      end
      line_break="\n".ord
      lbx, lby =base_x+line_break%16*cw,base_y+line_break/16*ch
      commands << "testforblocks #{lbx} #{lby} #{base_z} #{lbx} #{lby} #{base_z+7} #{MEM_VALUE[:x]} #{MEM_VALUE[:y]} #{MEM_VALUE[:z]}"
      nx, ny, nz = DISPLAY[:next][:x], DISPLAY[:next][:y], DISPLAY[:next][:z]
      commands << ["setblock #{nx+1} #{ny+1} #{nz+2} redstone_block"]
      commands << "testforblock #{nx+1} #{ny+1} #{nz+2} air"
      commands << ["setblock #{nx} #{ny+1} #{nz+2} redstone_block"]
      commands << "clone #{nx} #{ny+1} #{nz+2} #{nx+1} #{ny+1} #{nz+2} #{nx} #{ny} #{nz+2}"
      commands << "fill #{nx} #{ny+1} #{nz+2} #{nx+1} #{ny+1} #{nz+2} air"
      set_command_blocks world, commands, OP_PUTC;
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
      set_command_blocks(world, op_add_commands(MEM_VALUE), OP_ADD);
      set_command_blocks(world, op_mult_commands(MEM_VALUE), OP_MULT);
      set_command_blocks(world, op_gt_commands(MEM_VALUE), OP_GT);
      set_command_blocks(world, op_gt_commands(MEM_VALUE, eq: true), OP_GTEQ);
      set_command_blocks(world, op_gt_commands(MEM_VALUE, swap: true), OP_LT);
      set_command_blocks(world, op_gt_commands(MEM_VALUE, swap: true, eq: true), OP_LTEQ);
      set_command_blocks(world, op_mem_commands(:get), OP_MEM_READ)
      set_command_blocks(world, op_mem_commands(:set), OP_MEM_WRITE)

      done_reset_pos = [OP_DONE[:x], OP_DONE[:z]+1, OP_DONE[:y]]
      world[*done_reset_pos] = MCWorld::Block::CommandBlock.z_plus
      world.tile_entities[*done_reset_pos] = command_data "setblock #{mc_pos OP_DONE} air", redstone: true

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
  add_compiled_code DSL::Runtime.new{
    variable :a, :b, :c
    var.a = '0'
    exec_while(var.a) do
      "Hello World".chars.each do |c|
        putc c
      end
      var.a += 1
      putc var.a
      putc "\n"
    end
  }.compile
  File.write outfile, @world.encode
end
