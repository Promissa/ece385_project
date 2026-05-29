//-------------------------------------------------------------------------
// Minimal playable FC Galaxian-inspired VGA game.
//
// Controls from USB keyboard HID keycodes:
//   Left/Right arrows or A/D: move horizontally
//   Up/Down arrows or W/S: move vertically
//   Space: fire
//   Enter/Space: start
//   R: restart after game over
//-------------------------------------------------------------------------

module fc_galaxian_game(
    input  logic       clk,
    input  logic       reset_n,
    input  logic [7:0] keycode,
    input  logic [17:0] switches,

    output logic [3:0] difficulty_level,
    output logic [3:0] red,
    output logic [3:0] green,
    output logic [3:0] blue,
    output logic       hs,
    output logic       vs,
    output logic       pixel_clk,
    output logic       blank,
    output logic       sync
);

    localparam int SCREEN_W        = 640;
    localparam int SCREEN_H        = 480;
    localparam int PLAYER_W        = 32;
    localparam int PLAYER_H        = 18;
    localparam int PLAYER_START_Y  = 432;
    localparam int PLAYER_MIN_Y    = 344;
    localparam int PLAYER_MAX_Y    = 452;
    localparam int PLAYER_STEP     = 5;
    localparam int PLAYER_MAX_BULLETS = 4;
    localparam int PLAYER_BULLET_W = 4;
    localparam int PLAYER_BULLET_H = 12;
    localparam int ENEMY_MAX_BULLETS = 4;
    localparam int ENEMY_ROWS      = 4;
    localparam int ENEMY_COLS      = 8;
    localparam int ENEMY_COUNT     = ENEMY_ROWS * ENEMY_COLS;
    localparam int ENEMY_W         = 24;
    localparam int ENEMY_H         = 16;
    localparam int ENEMY_X_STEP    = 56;
    localparam int ENEMY_Y_STEP    = 34;
    localparam int ENEMY_MOVE_X    = 4;
    localparam int ENEMY_MOVE_Y    = 16;

    typedef enum logic [1:0] {
        ST_TITLE,
        ST_PLAY,
        ST_LIFE_LOST,
        ST_GAME_OVER
    } game_state_t;

    game_state_t state;

    logic [9:0] draw_x, draw_y;
    logic [9:0] draw_x_d, draw_y_d;
    logic       frame_tick;

    logic [9:0] player_x, player_y;
    logic [PLAYER_MAX_BULLETS-1:0] player_bullet_active;
    logic [9:0] player_bullet_x [PLAYER_MAX_BULLETS];
    logic [9:0] player_bullet_y [PLAYER_MAX_BULLETS];
    logic [ENEMY_MAX_BULLETS-1:0] enemy_bullet_active;
    logic [9:0] enemy_bullet_x [ENEMY_MAX_BULLETS];
    logic [9:0] enemy_bullet_y [ENEMY_MAX_BULLETS];

    logic [ENEMY_COUNT-1:0] enemy_alive;
    logic signed [10:0] enemy_base_x;
    logic [9:0] enemy_base_y;
    logic enemy_dir_right;

    logic [3:0] lives;
    logic [3:0] wave;
    logic [7:0] move_timer;
    logic [7:0] enemy_fire_timer;
    logic [7:0] fire_cooldown;
    logic [5:0] respawn_timer;
    logic [5:0] attack_cursor;
    logic       fire_prev;

    logic key_left, key_right, key_up, key_down, key_fire, key_start, key_restart;
    logic bullet_hit_enemy;
    int   bullet_hit_index;
    int   bullet_hit_player_bullet_index;
    logic player_hit_by_enemy;
    int   player_hit_enemy_bullet_index;
    logic enemy_fire_candidate_valid;
    int   enemy_fire_candidate_index;
    logic [5:0] enemies_remaining;
    logic player_bullet_free_valid;
    int   player_bullet_free_index;
    logic enemy_bullet_free_valid;
    int   enemy_bullet_free_index;
    logic [2:0] player_bullet_limit, enemy_bullet_limit;

    logic [3:0] score_thousands, score_hundreds, score_tens, score_ones;

    assign key_left    = (keycode == 8'h50) || (keycode == 8'h04); // left, A
    assign key_right   = (keycode == 8'h4F) || (keycode == 8'h07); // right, D
    assign key_up      = (keycode == 8'h52) || (keycode == 8'h1A); // up, W
    assign key_down    = (keycode == 8'h51) || (keycode == 8'h16); // down, S
    assign key_fire    = (keycode == 8'h2C); // space
    assign key_start   = (keycode == 8'h28) || (keycode == 8'h58) || key_fire; // enter, keypad enter, or fire
    assign key_restart = (keycode == 8'h15); // R
    assign player_bullet_limit = {1'b0, switches[9:8]} + 3'd1;
    assign enemy_bullet_limit  = {1'b0, switches[13:12]} + 3'd1;

    vga_controller vga_ctrl (
        .Clk       (clk),
        .Reset     (~reset_n),
        .hs        (hs),
        .vs        (vs),
        .pixel_clk (pixel_clk),
        .blank     (blank),
        .sync      (sync),
        .DrawX     (draw_x),
        .DrawY     (draw_y)
    );

    always_ff @(posedge clk) begin
        if (~reset_n) begin
            draw_x_d   <= 10'd0;
            draw_y_d   <= 10'd0;
            frame_tick <= 1'b0;
        end
        else begin
            draw_x_d   <= draw_x;
            draw_y_d   <= draw_y;
            frame_tick <= (draw_x == 10'd0) && (draw_y == 10'd0) &&
                          ((draw_x_d != 10'd0) || (draw_y_d != 10'd0));
        end
    end

    function automatic logic rect(
        input int px,
        input int py,
        input int x0,
        input int y0,
        input int w,
        input int h
    );
        begin
            rect = (px >= x0) && (px < (x0 + w)) && (py >= y0) && (py < (y0 + h));
        end
    endfunction

    function automatic logic overlap(
        input int ax,
        input int ay,
        input int aw,
        input int ah,
        input int bx,
        input int by,
        input int bw,
        input int bh
    );
        begin
            overlap = (ax < (bx + bw)) && ((ax + aw) > bx) &&
                      (ay < (by + bh)) && ((ay + ah) > by);
        end
    endfunction

    function automatic int enemy_x_pos(input int idx);
        begin
            enemy_x_pos = enemy_base_x + (idx % ENEMY_COLS) * ENEMY_X_STEP;
        end
    endfunction

    function automatic int enemy_y_pos(input int idx);
        begin
            enemy_y_pos = enemy_base_y + (idx / ENEMY_COLS) * ENEMY_Y_STEP;
        end
    endfunction

    function automatic logic [3:0] capped_wave(input logic [4:0] value);
        begin
            capped_wave = (value > 5'd10) ? 4'd10 : value[3:0];
        end
    endfunction

    function automatic logic [7:0] enemy_move_period(input logic [3:0] value);
        logic [3:0] level;
        begin
            level = capped_wave(value);
            enemy_move_period = 8'd20 - {4'd0, level};
        end
    endfunction

    function automatic logic [7:0] enemy_fire_period(input logic [3:0] value);
        logic [3:0] level;
        begin
            level = capped_wave(value);
            enemy_fire_period = 8'd96 - ({4'd0, level} << 2) - ({4'd0, level} << 1);
        end
    endfunction

    function automatic logic [9:0] enemy_bullet_speed(input logic [3:0] value);
        logic [3:0] level;
        begin
            level = capped_wave(value);
            enemy_bullet_speed = 10'd4 + {7'd0, level[3:1]};
        end
    endfunction

    function automatic logic [9:0] enemy_wave_start_y(input logic [3:0] value);
        logic [3:0] level;
        begin
            level = capped_wave(value);
            enemy_wave_start_y = 10'd72 + ({6'd0, level} << 2);
        end
    endfunction

    assign difficulty_level = capped_wave({1'b0, wave} + {3'b000, switches[17:16]});

    always_comb begin
        enemies_remaining = 6'd0;
        bullet_hit_enemy  = 1'b0;
        bullet_hit_index  = 0;
        bullet_hit_player_bullet_index = 0;
        player_hit_by_enemy = 1'b0;
        player_hit_enemy_bullet_index = 0;
        enemy_fire_candidate_valid = 1'b0;
        enemy_fire_candidate_index = 0;
        player_bullet_free_valid = 1'b0;
        player_bullet_free_index = 0;
        enemy_bullet_free_valid = 1'b0;
        enemy_bullet_free_index = 0;

        for (int b = 0; b < PLAYER_MAX_BULLETS; b++) begin
            if (!player_bullet_free_valid &&
                (b < player_bullet_limit) && !player_bullet_active[b]) begin
                player_bullet_free_valid = 1'b1;
                player_bullet_free_index = b;
            end
        end

        for (int b = 0; b < ENEMY_MAX_BULLETS; b++) begin
            if (!enemy_bullet_free_valid &&
                (b < enemy_bullet_limit) && !enemy_bullet_active[b]) begin
                enemy_bullet_free_valid = 1'b1;
                enemy_bullet_free_index = b;
            end

            if (enemy_bullet_active[b] && !player_hit_by_enemy) begin
                if (overlap(enemy_bullet_x[b], enemy_bullet_y[b], 6, 12,
                            player_x, player_y, PLAYER_W, PLAYER_H)) begin
                    player_hit_by_enemy = 1'b1;
                    player_hit_enemy_bullet_index = b;
                end
            end
        end

        for (int i = 0; i < ENEMY_COUNT; i++) begin
            if (enemy_alive[i])
                enemies_remaining = enemies_remaining + 6'd1;

            for (int b = 0; b < PLAYER_MAX_BULLETS; b++) begin
                if (player_bullet_active[b] && enemy_alive[i] && !bullet_hit_enemy) begin
                    if (overlap(player_bullet_x[b], player_bullet_y[b], PLAYER_BULLET_W, PLAYER_BULLET_H,
                                enemy_x_pos(i), enemy_y_pos(i), ENEMY_W, ENEMY_H)) begin
                        bullet_hit_enemy = 1'b1;
                        bullet_hit_index = i;
                        bullet_hit_player_bullet_index = b;
                    end
                end
            end

            if (!enemy_fire_candidate_valid &&
                enemy_alive[(attack_cursor + i) % ENEMY_COUNT]) begin
                enemy_fire_candidate_index = (attack_cursor + i) % ENEMY_COUNT;
                enemy_fire_candidate_valid = 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (~reset_n) begin
            state                <= ST_TITLE;
            player_x             <= 10'd304;
            player_bullet_active <= 1'b0;
            enemy_bullet_active  <= 1'b0;
            enemy_alive          <= {ENEMY_COUNT{1'b1}};
            enemy_base_x         <= 11'sd70;
            enemy_base_y         <= 10'd84;
            enemy_dir_right      <= 1'b1;
            lives                <= 4'd3;
            score_thousands      <= 4'd0;
            score_hundreds       <= 4'd0;
            score_tens           <= 4'd0;
            score_ones           <= 4'd0;
            wave                 <= 4'd1;
            move_timer           <= 8'd0;
            enemy_fire_timer     <= 8'd0;
            fire_cooldown        <= 8'd0;
            respawn_timer        <= 6'd0;
            attack_cursor        <= 6'd0;
            fire_prev            <= 1'b0;
            player_y             <= PLAYER_START_Y;
        end
        else if (frame_tick) begin
            fire_prev <= key_fire;

            if (fire_cooldown != 8'd0)
                fire_cooldown <= fire_cooldown - 8'd1;

            unique case (state)
                ST_TITLE: begin
                    player_x             <= 10'd304;
                    player_y             <= PLAYER_START_Y;
                    player_bullet_active <= 1'b0;
                    enemy_bullet_active  <= 1'b0;
                    enemy_alive          <= {ENEMY_COUNT{1'b1}};
                    enemy_base_x         <= 11'sd70;
                    enemy_base_y         <= 10'd84;
                    enemy_dir_right      <= 1'b1;
                    lives                <= 4'd3;
                    score_thousands      <= 4'd0;
                    score_hundreds       <= 4'd0;
                    score_tens           <= 4'd0;
                    score_ones           <= 4'd0;
                    wave                 <= 4'd1;
                    move_timer           <= 8'd0;
                    enemy_fire_timer     <= 8'd0;
                    attack_cursor        <= 6'd0;

                    if (key_start)
                        state <= ST_PLAY;
                end

                ST_PLAY: begin
                    if (key_left && (player_x > PLAYER_STEP))
                        player_x <= player_x - PLAYER_STEP;
                    else if (key_right && (player_x < SCREEN_W - PLAYER_W - PLAYER_STEP))
                        player_x <= player_x + PLAYER_STEP;

                    if (key_up && (player_y > PLAYER_MIN_Y + PLAYER_STEP))
                        player_y <= player_y - PLAYER_STEP;
                    else if (key_down && (player_y < PLAYER_MAX_Y - PLAYER_STEP))
                        player_y <= player_y + PLAYER_STEP;

                    if (key_fire && !fire_prev && player_bullet_free_valid && (fire_cooldown == 8'd0)) begin
                        player_bullet_active[player_bullet_free_index] <= 1'b1;
                        player_bullet_x[player_bullet_free_index]      <= player_x + (PLAYER_W / 2) - (PLAYER_BULLET_W / 2);
                        player_bullet_y[player_bullet_free_index]      <= player_y - PLAYER_BULLET_H;
                        fire_cooldown                                  <= 8'd10;
                    end

                    for (int b = 0; b < PLAYER_MAX_BULLETS; b++) begin
                        if (b >= player_bullet_limit) begin
                            player_bullet_active[b] <= 1'b0;
                        end
                        else if (player_bullet_active[b]) begin
                            if (player_bullet_y[b] <= 10'd30)
                                player_bullet_active[b] <= 1'b0;
                            else
                                player_bullet_y[b] <= player_bullet_y[b] - 10'd8;
                        end
                    end

                    if (bullet_hit_enemy) begin
                        enemy_alive[bullet_hit_index] <= 1'b0;
                        player_bullet_active[bullet_hit_player_bullet_index] <= 1'b0;
                        if (score_tens != 4'd9) begin
                            score_tens <= score_tens + 4'd1;
                        end
                        else begin
                            score_tens <= 4'd0;
                            if (score_hundreds != 4'd9) begin
                                score_hundreds <= score_hundreds + 4'd1;
                            end
                            else begin
                                score_hundreds <= 4'd0;
                                if (score_thousands != 4'd9)
                                    score_thousands <= score_thousands + 4'd1;
                            end
                        end

                        if (enemies_remaining <= 6'd1) begin
                            enemy_alive          <= {ENEMY_COUNT{1'b1}};
                            enemy_base_x         <= 11'sd70;
                            enemy_base_y         <= enemy_wave_start_y(wave);
                            enemy_dir_right      <= 1'b1;
                            enemy_bullet_active  <= 1'b0;
                            player_bullet_active <= 1'b0;
                            if (wave != 4'd15)
                                wave <= wave + 4'd1;
                        end
                    end

                    if (move_timer >= enemy_move_period(difficulty_level)) begin
                        move_timer <= 8'd0;
                        if (enemy_dir_right) begin
                            if ((enemy_base_x + ((ENEMY_COLS - 1) * ENEMY_X_STEP) + ENEMY_W + ENEMY_MOVE_X) >= 11'sd620) begin
                                enemy_dir_right <= 1'b0;
                                enemy_base_y    <= enemy_base_y + ENEMY_MOVE_Y;
                            end
                            else begin
                                enemy_base_x <= enemy_base_x + ENEMY_MOVE_X;
                            end
                        end
                        else begin
                            if (enemy_base_x <= 11'sd20) begin
                                enemy_dir_right <= 1'b1;
                                enemy_base_y    <= enemy_base_y + ENEMY_MOVE_Y;
                            end
                            else begin
                                enemy_base_x <= enemy_base_x - ENEMY_MOVE_X;
                            end
                        end
                    end
                    else begin
                        move_timer <= move_timer + 8'd1;
                    end

                    for (int b = 0; b < ENEMY_MAX_BULLETS; b++) begin
                        if (b >= enemy_bullet_limit) begin
                            enemy_bullet_active[b] <= 1'b0;
                        end
                        else if (enemy_bullet_active[b]) begin
                            if (enemy_bullet_y[b] >= SCREEN_H - 12)
                                enemy_bullet_active[b] <= 1'b0;
                            else
                                enemy_bullet_y[b] <= enemy_bullet_y[b] + enemy_bullet_speed(difficulty_level);
                        end
                    end

                    if (player_hit_by_enemy) begin
                        enemy_bullet_active[player_hit_enemy_bullet_index] <= 1'b0;
                        player_bullet_active <= {PLAYER_MAX_BULLETS{1'b0}};
                        if (lives <= 4'd1) begin
                            lives <= 4'd0;
                            state <= ST_GAME_OVER;
                        end
                        else begin
                            lives         <= lives - 4'd1;
                            respawn_timer <= 6'd45;
                            state         <= ST_LIFE_LOST;
                        end
                    end
                    else if (enemy_fire_timer >= enemy_fire_period(difficulty_level)) begin
                        enemy_fire_timer <= 8'd0;
                        if (enemy_fire_candidate_valid && enemy_bullet_free_valid) begin
                            enemy_bullet_active[enemy_bullet_free_index] <= 1'b1;
                            enemy_bullet_x[enemy_bullet_free_index]      <= enemy_x_pos(enemy_fire_candidate_index) + (ENEMY_W / 2);
                            enemy_bullet_y[enemy_bullet_free_index]      <= enemy_y_pos(enemy_fire_candidate_index) + ENEMY_H;
                            attack_cursor                                <= enemy_fire_candidate_index[5:0] + 6'd1;
                        end
                    end
                    else begin
                        enemy_fire_timer <= enemy_fire_timer + 8'd1;
                    end

                    if ((enemy_base_y + ((ENEMY_ROWS - 1) * ENEMY_Y_STEP) + ENEMY_H) >= player_y) begin
                        lives <= 4'd0;
                        state <= ST_GAME_OVER;
                    end
                end

                ST_LIFE_LOST: begin
                    player_x             <= 10'd304;
                    player_y             <= PLAYER_START_Y;
                    player_bullet_active <= 1'b0;
                    enemy_bullet_active  <= 1'b0;

                    if (respawn_timer != 6'd0)
                        respawn_timer <= respawn_timer - 6'd1;
                    else
                        state <= ST_PLAY;
                end

                ST_GAME_OVER: begin
                    player_bullet_active <= 1'b0;
                    enemy_bullet_active  <= 1'b0;
                    if (key_restart || key_start) begin
                        player_x             <= 10'd304;
                        player_y             <= PLAYER_START_Y;
                        player_bullet_active <= 1'b0;
                        enemy_bullet_active  <= 1'b0;
                        enemy_alive          <= {ENEMY_COUNT{1'b1}};
                        enemy_base_x         <= 11'sd70;
                        enemy_base_y         <= 10'd84;
                        enemy_dir_right      <= 1'b1;
                        lives                <= 4'd3;
                        score_thousands      <= 4'd0;
                        score_hundreds       <= 4'd0;
                        score_tens           <= 4'd0;
                        score_ones           <= 4'd0;
                        wave                 <= 4'd1;
                        move_timer           <= 8'd0;
                        enemy_fire_timer     <= 8'd0;
                        fire_cooldown        <= 8'd0;
                        respawn_timer        <= 6'd0;
                        attack_cursor        <= 6'd0;
                        state                <= ST_PLAY;
                    end
                end

                default: state <= ST_TITLE;
            endcase
        end
    end

    function automatic logic [4:0] glyph_row(input logic [6:0] ch, input logic [2:0] row);
        begin
            glyph_row = 5'b00000;
            unique case (ch)
                7'd48: unique case (row)
                    0: glyph_row = 5'b01110; 1: glyph_row = 5'b10001; 2: glyph_row = 5'b10011;
                    3: glyph_row = 5'b10101; 4: glyph_row = 5'b11001; 5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b01110; default: glyph_row = 5'b00000;
                endcase
                7'd49: unique case (row)
                    0: glyph_row = 5'b00100; 1: glyph_row = 5'b01100; 2: glyph_row = 5'b00100;
                    3: glyph_row = 5'b00100; 4: glyph_row = 5'b00100; 5: glyph_row = 5'b00100;
                    6: glyph_row = 5'b01110; default: glyph_row = 5'b00000;
                endcase
                7'd50: unique case (row)
                    0: glyph_row = 5'b01110; 1: glyph_row = 5'b10001; 2: glyph_row = 5'b00001;
                    3: glyph_row = 5'b00010; 4: glyph_row = 5'b00100; 5: glyph_row = 5'b01000;
                    6: glyph_row = 5'b11111; default: glyph_row = 5'b00000;
                endcase
                7'd51: unique case (row)
                    0: glyph_row = 5'b11110; 1: glyph_row = 5'b00001; 2: glyph_row = 5'b00001;
                    3: glyph_row = 5'b01110; 4: glyph_row = 5'b00001; 5: glyph_row = 5'b00001;
                    6: glyph_row = 5'b11110; default: glyph_row = 5'b00000;
                endcase
                7'd52: unique case (row)
                    0: glyph_row = 5'b00010; 1: glyph_row = 5'b00110; 2: glyph_row = 5'b01010;
                    3: glyph_row = 5'b10010; 4: glyph_row = 5'b11111; 5: glyph_row = 5'b00010;
                    6: glyph_row = 5'b00010; default: glyph_row = 5'b00000;
                endcase
                7'd53: unique case (row)
                    0: glyph_row = 5'b11111; 1: glyph_row = 5'b10000; 2: glyph_row = 5'b11110;
                    3: glyph_row = 5'b00001; 4: glyph_row = 5'b00001; 5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b01110; default: glyph_row = 5'b00000;
                endcase
                7'd54: unique case (row)
                    0: glyph_row = 5'b00110; 1: glyph_row = 5'b01000; 2: glyph_row = 5'b10000;
                    3: glyph_row = 5'b11110; 4: glyph_row = 5'b10001; 5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b01110; default: glyph_row = 5'b00000;
                endcase
                7'd55: unique case (row)
                    0: glyph_row = 5'b11111; 1: glyph_row = 5'b00001; 2: glyph_row = 5'b00010;
                    3: glyph_row = 5'b00100; 4: glyph_row = 5'b01000; 5: glyph_row = 5'b01000;
                    6: glyph_row = 5'b01000; default: glyph_row = 5'b00000;
                endcase
                7'd56: unique case (row)
                    0: glyph_row = 5'b01110; 1: glyph_row = 5'b10001; 2: glyph_row = 5'b10001;
                    3: glyph_row = 5'b01110; 4: glyph_row = 5'b10001; 5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b01110; default: glyph_row = 5'b00000;
                endcase
                7'd57: unique case (row)
                    0: glyph_row = 5'b01110; 1: glyph_row = 5'b10001; 2: glyph_row = 5'b10001;
                    3: glyph_row = 5'b01111; 4: glyph_row = 5'b00001; 5: glyph_row = 5'b00010;
                    6: glyph_row = 5'b11100; default: glyph_row = 5'b00000;
                endcase
                7'd65: unique case (row) // A
                    0: glyph_row = 5'b01110; 1: glyph_row = 5'b10001; 2: glyph_row = 5'b10001;
                    3: glyph_row = 5'b11111; 4: glyph_row = 5'b10001; 5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b10001; default: glyph_row = 5'b00000;
                endcase
                7'd67: unique case (row) // C
                    0: glyph_row = 5'b01111; 1: glyph_row = 5'b10000; 2: glyph_row = 5'b10000;
                    3: glyph_row = 5'b10000; 4: glyph_row = 5'b10000; 5: glyph_row = 5'b10000;
                    6: glyph_row = 5'b01111; default: glyph_row = 5'b00000;
                endcase
                7'd69: unique case (row) // E
                    0: glyph_row = 5'b11111; 1: glyph_row = 5'b10000; 2: glyph_row = 5'b10000;
                    3: glyph_row = 5'b11110; 4: glyph_row = 5'b10000; 5: glyph_row = 5'b10000;
                    6: glyph_row = 5'b11111; default: glyph_row = 5'b00000;
                endcase
                7'd70: unique case (row) // F
                    0: glyph_row = 5'b11111; 1: glyph_row = 5'b10000; 2: glyph_row = 5'b10000;
                    3: glyph_row = 5'b11110; 4: glyph_row = 5'b10000; 5: glyph_row = 5'b10000;
                    6: glyph_row = 5'b10000; default: glyph_row = 5'b00000;
                endcase
                7'd71: unique case (row) // G
                    0: glyph_row = 5'b01111; 1: glyph_row = 5'b10000; 2: glyph_row = 5'b10000;
                    3: glyph_row = 5'b10011; 4: glyph_row = 5'b10001; 5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b01111; default: glyph_row = 5'b00000;
                endcase
                7'd73: unique case (row) // I
                    0: glyph_row = 5'b11111; 1: glyph_row = 5'b00100; 2: glyph_row = 5'b00100;
                    3: glyph_row = 5'b00100; 4: glyph_row = 5'b00100; 5: glyph_row = 5'b00100;
                    6: glyph_row = 5'b11111; default: glyph_row = 5'b00000;
                endcase
                7'd76: unique case (row) // L
                    0: glyph_row = 5'b10000; 1: glyph_row = 5'b10000; 2: glyph_row = 5'b10000;
                    3: glyph_row = 5'b10000; 4: glyph_row = 5'b10000; 5: glyph_row = 5'b10000;
                    6: glyph_row = 5'b11111; default: glyph_row = 5'b00000;
                endcase
                7'd77: unique case (row) // M
                    0: glyph_row = 5'b10001; 1: glyph_row = 5'b11011; 2: glyph_row = 5'b10101;
                    3: glyph_row = 5'b10101; 4: glyph_row = 5'b10001; 5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b10001; default: glyph_row = 5'b00000;
                endcase
                7'd78: unique case (row) // N
                    0: glyph_row = 5'b10001; 1: glyph_row = 5'b11001; 2: glyph_row = 5'b10101;
                    3: glyph_row = 5'b10011; 4: glyph_row = 5'b10001; 5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b10001; default: glyph_row = 5'b00000;
                endcase
                7'd79: unique case (row) // O
                    0: glyph_row = 5'b01110; 1: glyph_row = 5'b10001; 2: glyph_row = 5'b10001;
                    3: glyph_row = 5'b10001; 4: glyph_row = 5'b10001; 5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b01110; default: glyph_row = 5'b00000;
                endcase
                7'd80: unique case (row) // P
                    0: glyph_row = 5'b11110; 1: glyph_row = 5'b10001; 2: glyph_row = 5'b10001;
                    3: glyph_row = 5'b11110; 4: glyph_row = 5'b10000; 5: glyph_row = 5'b10000;
                    6: glyph_row = 5'b10000; default: glyph_row = 5'b00000;
                endcase
                7'd82: unique case (row) // R
                    0: glyph_row = 5'b11110; 1: glyph_row = 5'b10001; 2: glyph_row = 5'b10001;
                    3: glyph_row = 5'b11110; 4: glyph_row = 5'b10100; 5: glyph_row = 5'b10010;
                    6: glyph_row = 5'b10001; default: glyph_row = 5'b00000;
                endcase
                7'd83: unique case (row) // S
                    0: glyph_row = 5'b01111; 1: glyph_row = 5'b10000; 2: glyph_row = 5'b10000;
                    3: glyph_row = 5'b01110; 4: glyph_row = 5'b00001; 5: glyph_row = 5'b00001;
                    6: glyph_row = 5'b11110; default: glyph_row = 5'b00000;
                endcase
                7'd84: unique case (row) // T
                    0: glyph_row = 5'b11111; 1: glyph_row = 5'b00100; 2: glyph_row = 5'b00100;
                    3: glyph_row = 5'b00100; 4: glyph_row = 5'b00100; 5: glyph_row = 5'b00100;
                    6: glyph_row = 5'b00100; default: glyph_row = 5'b00000;
                endcase
                7'd86: unique case (row) // V
                    0: glyph_row = 5'b10001; 1: glyph_row = 5'b10001; 2: glyph_row = 5'b10001;
                    3: glyph_row = 5'b10001; 4: glyph_row = 5'b10001; 5: glyph_row = 5'b01010;
                    6: glyph_row = 5'b00100; default: glyph_row = 5'b00000;
                endcase
                7'd88: unique case (row) // X
                    0: glyph_row = 5'b10001; 1: glyph_row = 5'b10001; 2: glyph_row = 5'b01010;
                    3: glyph_row = 5'b00100; 4: glyph_row = 5'b01010; 5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b10001; default: glyph_row = 5'b00000;
                endcase
                default: glyph_row = 5'b00000;
            endcase
        end
    endfunction

    function automatic logic [6:0] msg_char(input int msg, input int idx);
        begin
            msg_char = 7'd32;
            unique case (msg)
                0: unique case (idx) // FC GALAXIAN
                    0: msg_char = 7'd70; 1: msg_char = 7'd67; 2: msg_char = 7'd32;
                    3: msg_char = 7'd71; 4: msg_char = 7'd65; 5: msg_char = 7'd76;
                    6: msg_char = 7'd65; 7: msg_char = 7'd88; 8: msg_char = 7'd73;
                    9: msg_char = 7'd65; 10: msg_char = 7'd78; default: msg_char = 7'd32;
                endcase
                1: unique case (idx) // PRESS START
                    0: msg_char = 7'd80; 1: msg_char = 7'd82; 2: msg_char = 7'd69;
                    3: msg_char = 7'd83; 4: msg_char = 7'd83; 5: msg_char = 7'd32;
                    6: msg_char = 7'd83; 7: msg_char = 7'd84; 8: msg_char = 7'd65;
                    9: msg_char = 7'd82; 10: msg_char = 7'd84; default: msg_char = 7'd32;
                endcase
                2: unique case (idx) // GAME OVER
                    0: msg_char = 7'd71; 1: msg_char = 7'd65; 2: msg_char = 7'd77;
                    3: msg_char = 7'd69; 4: msg_char = 7'd32; 5: msg_char = 7'd79;
                    6: msg_char = 7'd86; 7: msg_char = 7'd69; 8: msg_char = 7'd82;
                    default: msg_char = 7'd32;
                endcase
                3: unique case (idx) // SCORE
                    0: msg_char = 7'd83; 1: msg_char = 7'd67; 2: msg_char = 7'd79;
                    3: msg_char = 7'd82; 4: msg_char = 7'd69; default: msg_char = 7'd32;
                endcase
                4: unique case (idx) // LIVES
                    0: msg_char = 7'd76; 1: msg_char = 7'd73; 2: msg_char = 7'd86;
                    3: msg_char = 7'd69; 4: msg_char = 7'd83; default: msg_char = 7'd32;
                endcase
                5: unique case (idx) // FINAL SCORE
                    0: msg_char = 7'd70; 1: msg_char = 7'd73; 2: msg_char = 7'd78;
                    3: msg_char = 7'd65; 4: msg_char = 7'd76; 5: msg_char = 7'd32;
                    6: msg_char = 7'd83; 7: msg_char = 7'd67; 8: msg_char = 7'd79;
                    9: msg_char = 7'd82; 10: msg_char = 7'd69; default: msg_char = 7'd32;
                endcase
                default: msg_char = 7'd32;
            endcase
        end
    endfunction

    function automatic int msg_len(input int msg);
        begin
            unique case (msg)
                0: msg_len = 11;
                1: msg_len = 11;
                2: msg_len = 9;
                3: msg_len = 5;
                4: msg_len = 5;
                5: msg_len = 11;
                default: msg_len = 0;
            endcase
        end
    endfunction

    function automatic logic char_pixel(
        input logic [6:0] ch,
        input int x0,
        input int y0,
        input int scale_shift,
        input int px,
        input int py
    );
        int dx, dy, row, col;
        logic [4:0] bits;
        begin
            dx = px - x0;
            dy = py - y0;
            row = dy >>> scale_shift;
            col = dx >>> scale_shift;
            bits = glyph_row(ch, row[2:0]);
            if ((dx >= 0) && (dy >= 0) && (row >= 0) && (row < 7) &&
                (col >= 0) && (col < 5))
                char_pixel = bits[4 - col];
            else
                char_pixel = 1'b0;
        end
    endfunction

    function automatic logic msg_pixel(
        input int msg,
        input int x0,
        input int y0,
        input int scale_shift,
        input int px,
        input int py
    );
        int dx, dy, char_idx, row, col;
        logic [6:0] ch;
        logic [4:0] bits;
        begin
            dx = px - x0;
            dy = py - y0;
            char_idx = dx >>> (3 + scale_shift);
            row = dy >>> scale_shift;
            col = (dx >>> scale_shift) & 7;
            ch = msg_char(msg, char_idx);
            bits = glyph_row(ch, row[2:0]);

            if ((dx >= 0) && (dy >= 0) &&
                (char_idx >= 0) && (char_idx < msg_len(msg)) &&
                (row >= 0) && (row < 7) && (col >= 0) && (col < 5))
                msg_pixel = bits[4 - col];
            else
                msg_pixel = 1'b0;
        end
    endfunction

    logic star_pixel, player_pixel, player_core_pixel;
    logic player_bullet_pixel, enemy_bullet_pixel;
    logic enemy_pixel, enemy_eye_pixel;
    logic title_pixel, start_pixel, gameover_pixel, score_label_pixel, lives_label_pixel;
    logic score_digit_pixel, final_score_label_pixel, final_score_digit_pixel, life_icon_pixel;
    logic [3:0] px_red, px_green, px_blue;

    always_comb begin
        star_pixel          = 1'b0;
        player_pixel        = 1'b0;
        player_core_pixel   = 1'b0;
        player_bullet_pixel = 1'b0;
        enemy_bullet_pixel  = 1'b0;
        enemy_pixel         = 1'b0;
        enemy_eye_pixel     = 1'b0;
        title_pixel         = 1'b0;
        start_pixel         = 1'b0;
        gameover_pixel      = 1'b0;
        score_label_pixel   = 1'b0;
        lives_label_pixel   = 1'b0;
        score_digit_pixel   = 1'b0;
        final_score_label_pixel = 1'b0;
        final_score_digit_pixel = 1'b0;
        life_icon_pixel     = 1'b0;

        star_pixel = (draw_y > 10'd32) &&
                     (((draw_x[5:0] == {draw_y[3:0], 2'b01}) && draw_y[0]) ||
                      ((draw_x[6:1] == (draw_y[7:2] ^ 6'h2D)) && draw_x[0] && draw_y[1]));

        player_pixel =
            rect(draw_x, draw_y, player_x + 14, player_y, 4, 4) ||
            rect(draw_x, draw_y, player_x + 10, player_y + 4, 12, 6) ||
            rect(draw_x, draw_y, player_x + 4,  player_y + 10, 24, 5) ||
            rect(draw_x, draw_y, player_x,      player_y + 14, PLAYER_W, 4);
        player_core_pixel = rect(draw_x, draw_y, player_x + 13, player_y + 5, 6, 6);

        for (int b = 0; b < PLAYER_MAX_BULLETS; b++) begin
            if (player_bullet_active[b])
                player_bullet_pixel = player_bullet_pixel ||
                    rect(draw_x, draw_y, player_bullet_x[b], player_bullet_y[b], PLAYER_BULLET_W, PLAYER_BULLET_H);
        end

        for (int b = 0; b < ENEMY_MAX_BULLETS; b++) begin
            if (enemy_bullet_active[b])
                enemy_bullet_pixel = enemy_bullet_pixel ||
                    rect(draw_x, draw_y, enemy_bullet_x[b], enemy_bullet_y[b], 6, 12);
        end

        for (int i = 0; i < ENEMY_COUNT; i++) begin
            if (enemy_alive[i]) begin
                if (rect(draw_x, draw_y, enemy_x_pos(i), enemy_y_pos(i), ENEMY_W, ENEMY_H)) begin
                    enemy_pixel = 1'b1;
                    if (rect(draw_x, draw_y, enemy_x_pos(i) + 5, enemy_y_pos(i) + 5, 4, 4) ||
                        rect(draw_x, draw_y, enemy_x_pos(i) + 15, enemy_y_pos(i) + 5, 4, 4))
                        enemy_eye_pixel = 1'b1;
                end
            end
        end

        title_pixel       = msg_pixel(0, 144, 76, 2, draw_x, draw_y);
        start_pixel       = msg_pixel(1, 232, 330, 1, draw_x, draw_y);
        gameover_pixel    = msg_pixel(2, 176, 190, 2, draw_x, draw_y);
        score_label_pixel = msg_pixel(3, 12, 8, 1, draw_x, draw_y);
        lives_label_pixel = msg_pixel(4, 472, 8, 1, draw_x, draw_y);

        score_digit_pixel =
            char_pixel(7'd48 + score_thousands, 98, 8, 1, draw_x, draw_y) ||
            char_pixel(7'd48 + score_hundreds,  114, 8, 1, draw_x, draw_y) ||
            char_pixel(7'd48 + score_tens,      130, 8, 1, draw_x, draw_y) ||
            char_pixel(7'd48 + score_ones,      146, 8, 1, draw_x, draw_y);

        final_score_label_pixel = msg_pixel(5, 144, 258, 2, draw_x, draw_y);
        final_score_digit_pixel =
            char_pixel(7'd48 + score_thousands, 256, 320, 2, draw_x, draw_y) ||
            char_pixel(7'd48 + score_hundreds,  288, 320, 2, draw_x, draw_y) ||
            char_pixel(7'd48 + score_tens,      320, 320, 2, draw_x, draw_y) ||
            char_pixel(7'd48 + score_ones,      352, 320, 2, draw_x, draw_y);

        for (int k = 0; k < 3; k++) begin
            if (k < lives) begin
                life_icon_pixel = life_icon_pixel ||
                    rect(draw_x, draw_y, 556 + k * 24, 10, 6, 6) ||
                    rect(draw_x, draw_y, 552 + k * 24, 16, 14, 5) ||
                    rect(draw_x, draw_y, 548 + k * 24, 21, 22, 4);
            end
        end

        px_red   = 4'h0;
        px_green = 4'h0;
        px_blue  = 4'h0;

        if (!blank || (draw_x >= SCREEN_W) || (draw_y >= SCREEN_H)) begin
            px_red   = 4'h0;
            px_green = 4'h0;
            px_blue  = 4'h0;
        end
        else if (title_pixel && (state == ST_TITLE)) begin
            px_red   = 4'hF;
            px_green = 4'hD;
            px_blue  = 4'h3;
        end
        else if (gameover_pixel && (state == ST_GAME_OVER)) begin
            px_red   = 4'hF;
            px_green = 4'h2;
            px_blue  = 4'h2;
        end
        else if ((final_score_label_pixel || final_score_digit_pixel) && (state == ST_GAME_OVER)) begin
            px_red   = 4'hF;
            px_green = 4'hD;
            px_blue  = 4'h3;
        end
        else if (start_pixel && ((state == ST_TITLE) || (state == ST_GAME_OVER))) begin
            px_red   = 4'hF;
            px_green = 4'hF;
            px_blue  = 4'hF;
        end
        else if (score_label_pixel || lives_label_pixel || score_digit_pixel || life_icon_pixel) begin
            px_red   = 4'h6;
            px_green = 4'hF;
            px_blue  = 4'hD;
        end
        else if (player_bullet_pixel) begin
            px_red   = 4'hF;
            px_green = 4'hF;
            px_blue  = 4'h6;
        end
        else if (enemy_bullet_pixel) begin
            px_red   = 4'hF;
            px_green = 4'h6;
            px_blue  = 4'h2;
        end
        else if (player_core_pixel) begin
            px_red   = 4'hF;
            px_green = 4'hF;
            px_blue  = 4'hF;
        end
        else if (player_pixel && (state != ST_TITLE)) begin
            px_red   = 4'h2;
            px_green = 4'hC;
            px_blue  = 4'hF;
        end
        else if (enemy_eye_pixel) begin
            px_red   = 4'h0;
            px_green = 4'h0;
            px_blue  = 4'h0;
        end
        else if (enemy_pixel && (state != ST_TITLE)) begin
            px_red   = 4'hE;
            px_green = 4'h4;
            px_blue  = 4'hD;
        end
        else if (star_pixel) begin
            px_red   = 4'h4;
            px_green = 4'h5;
            px_blue  = 4'h8;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            red   <= 4'h0;
            green <= 4'h0;
            blue  <= 4'h0;
        end
        else begin
            red   <= px_red;
            green <= px_green;
            blue  <= px_blue;
        end
    end

endmodule
