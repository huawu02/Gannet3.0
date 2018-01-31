function MRS_struct = GannetMask_GE(fname, dcm_dir, MRS_struct, dcm_dir2, ii)

warning('off','MATLAB:nearlySingularMatrix');
warning('off','MATLAB:qhullmx:InternalWarning');

if nargin == 3
    if isstruct(MRS_struct)
        dcm_dir2 = dcm_dir;
        ii = 1;
    else
        dcm_dir2 = MRS_struct;
        clear MRS_struct;
        MRS_struct.ii = 1;
        ii = 1;
    end
    
end

if nargin == 4
    if isnumeric(dcm_dir2)
        ii = dcm_dir2;
        dcm_dir2 = dcm_dir;
    else
        ii = 1;
    end
end

if nargin < 3
    MRS_struct.ii = 1;
    ii = 1;
    dcm_dir2 = dcm_dir;
end

% Parse P-file to extract voxel dimensions and offsets (MM: 171110)
if MRS_struct.p.GE.rdbm_rev_num >= 11.0
    % In 11.0 and later the header and data are stored as little-endian
    fid = fopen(fname, 'r', 'ieee-le');
else
    fid = fopen(fname, 'r', 'ieee-be');
end
fseek(fid, 1468, 'bof');
p_hdr_value = fread(fid, 12, 'integer*4'); % byte offsets to start of sub-header structures
fseek(fid, p_hdr_value(8), 'bof'); % set position to start of rdb_hdr_exam
o_hdr_value = fread(fid, p_hdr_value(9)-p_hdr_value(8), 'real*4');
if MRS_struct.p.GE.rdbm_rev_num == 16
    MRS_struct.p.voxdim(ii,:) = o_hdr_value(822:824)';
    MRS_struct.p.voxoff(ii,:) = o_hdr_value(825:827)';
elseif MRS_struct.p.GE.rdbm_rev_num == 24
    MRS_struct.p.voxdim(ii,:) = o_hdr_value(1228:1230)';
    MRS_struct.p.voxoff(ii,:) = o_hdr_value(1231:1233)';
end
MRS_struct.p.voxoff(ii,:) = MRS_struct.p.voxoff(ii,:) .* [-1 -1 1];

% MRS_struct.p.voxang is not contained in P-file header (really!)
% The rotation is adopted from the image on which the voxel was placed
% i.e. either the 3D T1 or a custom rotated localizer.
MRS_struct.p.voxang(ii,:) = [NaN NaN NaN]; % put as NaN for now - for output page
currdir = pwd;

% MM (180118)
cd(dcm_dir2);
dcm_list = dir;
dcm_list = dcm_list(~ismember({dcm_list.name}, {'.','..','.DS_Store'}));
dcm_list = cellstr(char(dcm_list.name));
dcm_list = dcm_list(cellfun(@isempty, strfind(dcm_list, '.nii')));

% Load dicoms
MRSRotHead = dicominfo(dcm_list{1});

cd(currdir);
currdir = pwd;
cd(dcm_dir);
dcm_list = dir;
dcm_list = dcm_list(~ismember({dcm_list.name}, {'.','..','.DS_Store'}));
dcm_list = cellstr(char(dcm_list.name));
dcm_list = dcm_list(cellfun(@isempty, strfind(dcm_list, '.nii'))); %#ok<*STRCLFH>
dcm_list = dcm_list(cellfun(@isempty, strfind(dcm_list, '.mat')));
hdr = spm_dicom_headers(char(dcm_list));
nii_file_dir = spm_dicom_convert(hdr, 'all', 'flat', 'nii');
cd(currdir);

nii_file = nii_file_dir.files{1};

V = spm_vol(nii_file);
[T1,XYZ] = spm_read_vols(V);

% Shift imaging voxel coordinates by half an imaging voxel so that the XYZ matrix
% tells us the x,y,z coordinates of the MIDDLE of that imaging voxel.
voxdim = abs(V.mat(1:3,1:3));
voxdim = voxdim(voxdim > 0.1);
voxdim = round(voxdim/1e-2)*1e-2; % MM (180130)
halfpixshift = -voxdim(1:3)/2;
%halfpixshift(3) = -halfpixshift(3);
XYZ = XYZ + repmat(halfpixshift, [1 size(XYZ,2)]);

ap_size = MRS_struct.p.voxdim(ii,2);
lr_size = MRS_struct.p.voxdim(ii,1);
cc_size = MRS_struct.p.voxdim(ii,3);
ap_off = MRS_struct.p.voxoff(ii,2);
lr_off = MRS_struct.p.voxoff(ii,1);
cc_off = MRS_struct.p.voxoff(ii,3);
%ap_ang = MRS_struct.p.voxang(2);
%lr_ang = MRS_struct.p.voxang(1);
%cc_ang = MRS_struct.p.voxang(3);

% We need to flip ap and lr axes to match NIFTI convention
ap_off = -ap_off;
lr_off = -lr_off;

% define the voxel - use x y z
% x - left = positive
% y - posterior = postive
% z - superior = positive
% vox_ctr = ...
%     [lr_size/2 -ap_size/2 cc_size/2 ;
%     -lr_size/2 -ap_size/2 cc_size/2 ;
%     -lr_size/2 ap_size/2 cc_size/2 ;
%     lr_size/2 ap_size/2 cc_size/2 ;
%     -lr_size/2 ap_size/2 -cc_size/2 ;
%     lr_size/2 ap_size/2 -cc_size/2 ;
%     lr_size/2 -ap_size/2 -cc_size/2 ;
%     -lr_size/2 -ap_size/2 -cc_size/2 ];

%vox_rot=rotmat*vox_ctr.';

% calculate corner coordinates relative to xyz origin
vox_ctr_coor = [lr_off ap_off cc_off];
vox_ctr_coor = repmat(vox_ctr_coor.', [1,8]);
% vox_corner = vox_rot+vox_ctr_coor;

% New code RAEE

MRS_Rot_RE   = MRSRotHead.ImageOrientationPatient;
MRS_Rot_RE   = reshape(MRS_Rot_RE',[3 2]);

edge1        = repmat(MRS_Rot_RE(:,1), [1 8]);
edge1(:,2:3) = -edge1(:,2:3);
edge1(:,5)   = -edge1(:,5);
edge1(:,8)   = -edge1(:,8);
edge1(1:2,:) = -edge1(1:2,:);

edge2        = repmat(MRS_Rot_RE(:,2), [1 8]);
edge2(:,1:2) = -edge2(:,1:2);
edge2(:,7)   = -edge2(:,7);
edge2(:,8)   = -edge2(:,8);
edge2(1:2,:) = -edge2(1:2,:);

edge3        = repmat(cross(MRS_Rot_RE(:,1),MRS_Rot_RE(:,2)),[1 8]);
edge3(:,5:8) = -edge3(:,5:8);
edge3(1:2,:) = -edge3(1:2,:);

vox_corner = vox_ctr_coor + lr_size/2 * edge1 + ap_size/2 * edge2 + cc_size/2 * edge3;

mask = zeros(1,size(XYZ,2));
sphere_radius = sqrt((lr_size/2)^2 + (ap_size/2)^2 + (cc_size/2)^2);
distance2voxctr = sqrt(sum((XYZ-repmat([lr_off ap_off cc_off].', [1 size(XYZ, 2)])).^2, 1));
sphere_mask(distance2voxctr <= sphere_radius) = 1;

mask(sphere_mask == 1) = 1;
XYZ_sphere = XYZ(:,sphere_mask == 1);

tri = delaunayn([vox_corner.'; [lr_off ap_off cc_off]]);
tn = tsearchn([vox_corner.'; [lr_off ap_off cc_off]], tri, XYZ_sphere.');
isinside = ~isnan(tn);
mask(sphere_mask==1) = isinside;

mask = reshape(mask, V.dim);

[~,metabfile]  = fileparts(fname);
fidoutmask     = fullfile(dcm_dir,[metabfile '_mask.nii']);
V_mask.fname   = fidoutmask;
V_mask.descrip = 'MRS_voxel_mask';
V_mask.dim     = V.dim;
V_mask.dt      = V.dt;
V_mask.mat     = V.mat;

spm_write_vol(V_mask,mask);

T1img = T1/max(T1(:));
T1img_mas = T1img + 0.2*mask;

% Build output

fidoutmask = cellstr(fidoutmask);
MRS_struct.mask.outfile(ii,:) = fidoutmask;

voxel_ctr      = [-lr_off -ap_off cc_off];
voxel_ctr(1:2) = -voxel_ctr(1:2);
voxel_search   = (XYZ(:,:)-repmat(voxel_ctr.',[1 size(XYZ,2)])).^2;
voxel_search   = sqrt(sum(voxel_search,1));
[~,index1]     = min(voxel_search);
[slice(1), slice(2), slice(3)] = ind2sub(V.dim,index1);

im1 = squeeze(T1img_mas(:,:,slice(3)));
im1 = im1(end:-1:1,end:-1:1)';
im3 = squeeze(T1img_mas(:,slice(2),:));
im3 = im3(end:-1:1,end:-1:1)';
im2 = squeeze(T1img_mas(slice(1),:,:));
im2 = im2(end:-1:1,end:-1:1)';

% MM (180130): Resize slices if voxel resolution in T1 image isn't
% isometric
if voxdim(1) ~= voxdim(2)
    a = max(voxdim([1 2])) ./ min(voxdim([1 2]));
    im1 = imresize(im1, [size(im1,1)*a size(im1,2)]);
end

if voxdim(1) ~= voxdim(3)
    a = max(voxdim([1 3])) ./ min(voxdim([1 3]));
    im3 = imresize(im3, [size(im3,1)*a size(im3,2)]);
end

if voxdim(2) ~= voxdim(3)
    a = max(voxdim([2 3])) ./ min(voxdim([2 3]));
    im2 = imresize(im2, [size(im2,1)*a size(im2,2)]);
end

size_max = max([max(size(im1)) max(size(im2)) max(size(im3))]);
three_plane_img = zeros([size_max 3*size_max]);
three_plane_img(:,1:size_max)              = image_center(im1, size_max);
three_plane_img(:,size_max*2+(1:size_max)) = image_center(im3, size_max);
three_plane_img(:,size_max+(1:size_max))   = image_center(im2, size_max);

MRS_struct.mask.img(ii,:,:)   = three_plane_img;
MRS_struct.mask.T1image(ii,:) = {nii_file};

warning('on','MATLAB:nearlySingularMatrix');
warning('on','MATLAB:qhullmx:InternalWarning');

end



